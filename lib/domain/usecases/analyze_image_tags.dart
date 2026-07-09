import 'package:nai_huishi/data/datasources/remote/wd_tagger_api_service.dart';

/// 分析图片标签用例：调用在线 SmilingWolf/wd-tagger Hugging Face Space。
class AnalyzeImageTagsUseCase {
  final WdTaggerApiService _remote;

  AnalyzeImageTagsUseCase({required WdTaggerApiService remote})
      : _remote = remote;

  WdTaggerApiService get remote => _remote;

  /// 分析图片标签：直接调用在线 API
  Future<WdTaggerResult> analyze({
    required String imagePath,
    required String modelRepo,
    double generalThreshold = 0.35,
    double characterThreshold = 0.85,
  }) async {
    return _remote.analyze(
      imagePath: imagePath,
      modelRepo: modelRepo,
      generalThreshold: generalThreshold,
      characterThreshold: characterThreshold,
    );
  }
}
