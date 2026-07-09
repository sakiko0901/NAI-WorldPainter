import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// 创建一个配置了 DoH DNS + IPv4 优先 + 宽松 TLS + 全量日志的 Dio 实例
Dio createRobustDio() {
  final dio = Dio()..httpClientAdapter = createRobustAdapter();

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      debugPrint('[网络日志] >>> ${options.method} ${options.baseUrl}${options.path}');
      handler.next(options);
    },
    onResponse: (response, handler) {
      debugPrint('[网络日志] <<< ${response.statusCode} ${response.requestOptions.baseUrl}${response.requestOptions.path}');
      handler.next(response);
    },
    onError: (error, handler) {
      debugPrint('[网络日志] !!! ${error.type} ${error.message}');
      debugPrint('[网络日志]   url: ${error.requestOptions.baseUrl}${error.requestOptions.path}');
      debugPrint('[网络日志]   status: ${error.response?.statusCode}');
      debugPrint('[网络日志]   response: ${error.response?.data}');
      handler.next(error);
    },
  ));

  return dio;
}

/// 仅创建 robust HttpClientAdapter (DoH + IPv4 优先 + 宽松 TLS)
/// 用于运行时替换 dio.httpClientAdapter,不重建整个 Dio 实例
HttpClientAdapter createRobustAdapter() {
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.idleTimeout = const Duration(minutes: 15);
      client.connectionFactory = _createDohConnection;
      client.connectionTimeout = const Duration(seconds: 15);
      client.badCertificateCallback = (X509Certificate cert, String host, int port) {
        debugPrint('[网络日志] badCertificate: host=$host port=$port');
        return true;
      };
      return client;
    },
  );
}

/// 用 DoH 解析域名，然后 IPv4 优先连接
/// 对于 https 请求，用 SecureSocket 包装并设置正确 SNI
Future<ConnectionTask<Socket>> _createDohConnection(
  Uri uri,
  String? proxyHost,
  int? proxyPort,
) async {
  final host = proxyHost ?? uri.host;
  final port = proxyPort ?? uri.port;
  final isSecure = uri.scheme == 'https';

  final asIp = InternetAddress.tryParse(host);
  if (asIp != null) {
    debugPrint('[网络日志] 直接IP连接: $host');
    return ConnectionTask.fromSocket(
      _connectAndUpgrade(host, port, isSecure),
      () {},
    );
  }

  debugPrint('[网络日志] DoH解析: $host');
  final addresses = await _dohLookup(host);
  final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4);
  final ipv6 = addresses.where((a) => a.type == InternetAddressType.IPv6);

  debugPrint('[网络日志] DoH结果: IPv4=${ipv4.map((a) => a.address).toList()} IPv6=${ipv6.map((a) => a.address).toList()}');

  final ordered = [...ipv4, ...ipv6];

  for (final addr in ordered) {
    try {
      debugPrint('[网络日志] 尝试连接: ${addr.address}:$port');
      final socket = await _connectAndUpgrade(addr.address, port, isSecure, sniHost: host);
      debugPrint('[网络日志] 连接成功: ${addr.address}:$port');
      return ConnectionTask.fromSocket(Future.value(socket), () {});
    } catch (e) {
      debugPrint('[网络日志] 连接失败: ${addr.address}:$port - $e');
    }
  }

  debugPrint('[网络日志] DoH全部失败，fallback本地DNS: $host');
  try {
    final localAddresses = await InternetAddress.lookup(host);
    for (final addr in localAddresses) {
      try {
        final socket = await _connectAndUpgrade(addr.address, port, isSecure, sniHost: host);
        debugPrint('[网络日志] 本地DNS连接成功: ${addr.address}:$port');
        return ConnectionTask.fromSocket(Future.value(socket), () {});
      } catch (_) {}
    }
  } catch (e) {
    debugPrint('[网络日志] 本地DNS也失败: $e');
  }

  throw SocketException('无法连接到 $host (DoH + 本地DNS均失败)');
}

/// 建立 TCP 连接，如果是 https 则升级为 SecureSocket（带正确 SNI）
Future<Socket> _connectAndUpgrade(String ip, int port, bool isSecure, {String? sniHost}) async {
  final tcpSocket = await Socket.connect(ip, port, timeout: const Duration(seconds: 10));

  if (!isSecure) return tcpSocket;

  // https: 用 SecureSocket 包装，设置 SNI 为原始域名
  try {
    return await SecureSocket.secure(
      tcpSocket,
      host: sniHost ?? ip,
      onBadCertificate: (_) => true,
    );
  } catch (e) {
    tcpSocket.destroy();
    rethrow;
  }
}

/// 通过国内 DoH 服务器解析域名
Future<List<InternetAddress>> _dohLookup(String domain) async {
  final results = <InternetAddress>[];

  const dohServers = [
    _DohServer(ip: '223.5.5.5', host: 'dns.alidns.com'),
    _DohServer(ip: '119.29.29.29', host: 'doh.pub'),
    _DohServer(ip: '1.12.12.12', host: 'doh.360.cn'),
  ];

  for (final server in dohServers) {
    try {
      debugPrint('[网络日志] DoH尝试: ${server.host} (${server.ip})');
      final resolved = await _queryDoh(server, domain);
      if (resolved.isNotEmpty) {
        results.addAll(resolved);
        debugPrint('[网络日志] DoH成功: ${server.host} -> ${resolved.map((a) => a.address).toList()}');
        return results;
      }
    } catch (e) {
      debugPrint('[网络日志] DoH失败: ${server.host} - $e');
    }
  }

  return results;
}

Future<List<InternetAddress>> _queryDoh(_DohServer server, String domain) async {
  final results = <InternetAddress>[];

  try {
    results.addAll(await _rawDohQuery(server, domain, 'A'));
  } catch (e) {
    debugPrint('[网络日志] DoH IPv4查询失败: $e');
  }

  try {
    results.addAll(await _rawDohQuery(server, domain, 'AAAA'));
  } catch (e) {
    debugPrint('[网络日志] DoH IPv6查询失败: $e');
  }

  return results;
}

Future<List<InternetAddress>> _rawDohQuery(
  _DohServer server,
  String domain,
  String type,
) async {
  final tcpSocket = await Socket.connect(
    server.ip,
    443,
    timeout: const Duration(seconds: 5),
  );

  late SecureSocket secureSocket;
  try {
    secureSocket = await SecureSocket.secure(
      tcpSocket,
      host: server.host,
      onBadCertificate: (_) => true,
    );
  } catch (e) {
    tcpSocket.destroy();
    rethrow;
  }

  final request = StringBuffer()
    ..write('GET /resolve?name=$domain&type=$type HTTP/1.1\r\n')
    ..write('Host: ${server.host}\r\n')
    ..write('Accept: application/dns-json\r\n')
    ..write('Connection: close\r\n')
    ..write('\r\n');

  secureSocket.write(request.toString());
  await secureSocket.flush();

  final responseText = await utf8.decoder.bind(secureSocket).join();
  secureSocket.destroy();

  final separator = responseText.indexOf('\r\n\r\n');
  if (separator == -1) {
    throw const FormatException('无效的 HTTP 响应');
  }

  final headers = responseText.substring(0, separator).toLowerCase();
  var body = responseText.substring(separator + 4);

  if (headers.contains('transfer-encoding: chunked')) {
    body = _decodeChunkedBody(body);
  }

  final json = jsonDecode(body) as Map<String, dynamic>;
  final answers = json['Answer'] as List<dynamic>?;
  final results = <InternetAddress>[];
  if (answers != null) {
    for (final answer in answers) {
      if (answer is Map<String, dynamic>) {
        final data = answer['data'] as String?;
        if (data != null && InternetAddress.tryParse(data) != null) {
          results.add(InternetAddress(data));
        }
      }
    }
  }

  return results;
}

String _decodeChunkedBody(String body) {
  final output = StringBuffer();
  var rest = body;

  while (rest.isNotEmpty) {
    final sizeLineEnd = rest.indexOf('\r\n');
    if (sizeLineEnd == -1) break;

    final sizeHex = rest.substring(0, sizeLineEnd).trim();
    final size = int.tryParse(sizeHex, radix: 16);
    if (size == null || size == 0) break;

    final chunkStart = sizeLineEnd + 2;
    final chunkEnd = chunkStart + size;
    if (chunkEnd > rest.length) break;

    output.write(rest.substring(chunkStart, chunkEnd));
    rest = rest.substring(chunkEnd + 2);
  }

  return output.toString();
}

class _DohServer {
  final String ip;
  final String host;
  const _DohServer({required this.ip, required this.host});
}
