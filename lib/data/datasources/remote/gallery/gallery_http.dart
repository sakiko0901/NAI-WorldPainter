import 'dart:convert';
import 'package:dio/dio.dart';

/// A separate client: gallery requests must never inherit generation credentials.
class GalleryHttp {
  final Dio dio;
  GalleryHttp(this.dio);

  static Dio createDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: false,
      ));

  static bool isPublicUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase().replaceAll(RegExp(r'\.+$'), '');
    if (!host.contains('.') ||
        RegExp(r'^\d+$').hasMatch(host.split('.').last)) {
      return false;
    }
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.contains(':')) {
      return false;
    }
    final ip = RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host);
    if (ip) return false;
    return true;
  }

  static Map<String, String> headers(String referer) => {
        'User-Agent': 'WorldPainter/1.2 (Android; OnlineGallery)',
        'Referer': referer,
        'Accept': 'application/json, text/html;q=0.9, */*;q=0.8',
      };

  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? params,
    String? referer,
    ResponseType responseType = ResponseType.plain,
  }) async {
    var uri = Uri.parse(url);
    if (params != null) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        ...params.map((k, v) => MapEntry(k, v.toString())),
      });
    }
    for (var hop = 0; hop < 5; hop++) {
      if (!isPublicUrl(uri.toString())) throw StateError('图库地址不受支持');
      final cancel = CancelToken();
      final response = await dio.getUri<dynamic>(uri,
          options: Options(
            responseType: responseType,
            followRedirects: false,
            headers: headers(referer ?? '${uri.origin}/'),
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
          cancelToken: cancel,
          onReceiveProgress: responseType == ResponseType.stream
              ? null
              : (received, total) {
                  if (received > 24 * 1024 * 1024 || total > 24 * 1024 * 1024) {
                    cancel.cancel('图库数据超过读取上限');
                  }
                });
      if ((response.statusCode ?? 200) < 300) return response;
      final body = response.data;
      if (body is ResponseBody) {
        await body.stream.listen(null).cancel();
      }
      final location = response.headers.value('location');
      if (location == null) throw StateError('图库跳转地址缺失');
      uri = uri.resolve(location);
    }
    throw StateError('图库跳转次数过多');
  }

  Future<dynamic> json(String url,
      {Map<String, dynamic>? params, String? referer}) async {
    final data = (await get(url, params: params, referer: referer)).data;
    return data is String ? jsonDecode(data) : data;
  }

  Future<String> html(String url,
          {Map<String, dynamic>? params, String? referer}) async =>
      (await get(url, params: params, referer: referer)).data.toString();
}
