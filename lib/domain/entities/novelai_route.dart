import 'package:nai_huishi/core/constants/app_constants.dart';

import 'api_endpoint.dart';

enum NovelAiChannel { gateway7877, ikun, official }

class NovelAiRoute {
  final NovelAiChannel channel;

  const NovelAiRoute._(this.channel);

  factory NovelAiRoute.fromEndpoint(ApiEndpoint endpoint) =>
      NovelAiRoute.fromIds(endpoint.id, endpoint.protocol);

  factory NovelAiRoute.fromIds(String? endpointId, String? protocol) {
    if (endpointId == AppConstants.novelAiOfficialEndpointId) {
      return const NovelAiRoute._(NovelAiChannel.official);
    }
    if (endpointId == AppConstants.novelAiImageGenerationsEndpointId) {
      return const NovelAiRoute._(NovelAiChannel.ikun);
    }
    if (endpointId == AppConstants.novelAiChatCompletionsEndpointId) {
      return const NovelAiRoute._(NovelAiChannel.gateway7877);
    }
    if (protocol == AppConstants.novelAiOfficialProtocol) {
      return const NovelAiRoute._(NovelAiChannel.official);
    }
    if (protocol == AppConstants.novelAiImageGenerationsProtocol) {
      return const NovelAiRoute._(NovelAiChannel.ikun);
    }
    return const NovelAiRoute._(NovelAiChannel.gateway7877);
  }

  bool get isOfficial => channel == NovelAiChannel.official;
  bool get isIkun => channel == NovelAiChannel.ikun;
  bool get isGateway7877 => channel == NovelAiChannel.gateway7877;
  bool get supportsImg2Img => true;
  bool get supportsInpaint => true;
  bool get supportsVibe => true;
  bool get supportsPreciseReference => true;
  bool get supportsCharacters => true;
}
