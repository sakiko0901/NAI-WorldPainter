import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/core/constants/api_constants.dart';
import 'package:nai_huishi/core/errors/exceptions.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';

void main() {
  test('reads subscription from image domain with Bearer token and seconds',
      () async {
    final fixture = _SubscriptionAdapter({
      'tier': 3,
      'active': true,
      'expiresAt': 1790674321,
      'trainingStepsLeft': {
        'fixedTrainingStepsLeft': 9898,
        'purchasedTrainingSteps': 100,
      },
      'usage': {'percent': 46, 'isNegative': false},
    });
    final result = await _service(fixture).fetchV5Usage(' pst-test ');
    expect(fixture.requests.single.method, 'GET');
    expect(fixture.requests.single.uri.toString(),
        'https://image.novelai.net/user/subscription');
    expect(fixture.requests.single.headers['Authorization'], 'Bearer pst-test');
    expect(result!.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(1790674321000, isUtc: true));
    expect(result.percent, 46);
    expect(result.tier, 3);
    expect(result.totalAnlas, 9998);
  });

  test('retains expiry and Anlas without Opus usage or auto renewal', () async {
    final result = await _service(_SubscriptionAdapter({
      'tier': 1,
      'active': true,
      'expiresAt': '1790674321',
      'trainingStepsLeft': {'fixedTrainingStepsLeft': 1000},
    })).fetchV5Usage('pst-test');
    expect(result!.expiresAt!.millisecondsSinceEpoch, 1790674321000);
    expect(result.percent, isNull);
    expect(result.totalAnlas, 1000);
  });

  for (final expiry in [null, 0, -1, 'invalid', 8640000000001]) {
    test('unavailable expiry $expiry does not hide valid quota', () async {
      final result = await _service(_SubscriptionAdapter({
        'expiresAt': expiry,
        'usage': {'percent': 90, 'isNegative': false},
      })).fetchV5Usage('pst-test');
      expect(result!.expiresAt, isNull);
      expect(result.percent, 90);
    });
  }

  test('still accepts a wrapped subscription response', () async {
    final result = await _service(_SubscriptionAdapter({
      'subscription': {
        'expiresAt': 1790674321,
        'usage': {'percent': 0, 'isNegative': true},
      },
    })).fetchV5Usage('pst-test');
    expect(result!.expiresAt, isNotNull);
    expect(result.percent, 0);
    expect(result.isNegative, isTrue);
  });

  test('query errors remain errors instead of inventing an expiry', () async {
    await expectLater(
      _service(_SubscriptionAdapter({'message': 'Unauthorized'}, status: 401))
          .fetchV5Usage('pst-test'),
      throwsA(isA<ApiException>()),
    );
  });

  test('custom channels never request official subscriptions', () async {
    final fixture = _SubscriptionAdapter({});
    final service = _service(fixture).forBaseUrl('https://relay.example');
    expect(await service.fetchV5Usage('custom-token'), isNull);
    expect(fixture.requests, isEmpty);
  });
}

OfficialNovelAiApiService _service(_SubscriptionAdapter adapter) =>
    OfficialNovelAiApiService(Dio(BaseOptions(
      baseUrl: ApiConstants.officialImageBaseUrl,
    ))
      ..httpClientAdapter = adapter);

class _SubscriptionAdapter implements HttpClientAdapter {
  final Map<String, dynamic> body;
  final int status;
  final requests = <RequestOptions>[];

  _SubscriptionAdapter(this.body, {this.status = 200});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}
