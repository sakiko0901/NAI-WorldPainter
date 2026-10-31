import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/domain/entities/sr_model.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/domain/usecases/upscale_image.dart';

/// 超分任务状态
enum SrStatus { idle, running, success, failed }

/// 图片增强（超分）ViewModel
class SuperResolutionViewModel extends ChangeNotifier {
  final UpscaleImageUseCase _upscale;
  final SaveImageUseCase _saveImage;

  final AppUpdateInstallGuard? _updateGuard;

  SuperResolutionViewModel(this._upscale, this._saveImage,
      {AppUpdateInstallGuard? updateGuard})
      : _updateGuard = updateGuard;

  /// 待处理的输入图片路径
  String? _inputPath;
  String? get inputPath => _inputPath;

  /// 超分输出路径
  String? _outputPath;
  String? get outputPath => _outputPath;

  /// 选中的模型
  SrModel _model = SrModel.presets.first;
  SrModel get model => _model;

  SrStatus _status = SrStatus.idle;
  SrStatus get status => _status;
  bool get isRunning => _status == SrStatus.running;

  /// 最近一行进度日志
  String _progress = '';
  String get progress => _progress;

  /// 解析自原生输出的当前进度（0~1）。无法解析时为 null（页面回退为不确定进度）。
  double? _progressValue;
  double? get progressValue => _progressValue;

  String? _error;
  String? get error => _error;

  /// ncnn CLI 的进度行通常形如 "12.34%"。匹配出百分比。
  static final RegExp _percentRe = RegExp(r'(\d+(?:\.\d+)?)\s*%');

  void selectInput(String path) {
    _inputPath = path;
    _outputPath = null;
    _status = SrStatus.idle;
    _progress = '';
    _progressValue = null;
    _error = null;
    notifyListeners();
  }

  void selectModel(SrModel model) {
    _model = model;
    notifyListeners();
  }

  Future<void> run() async {
    if (_updateGuard?.isInstalling ?? false) {
      _error = '正在安装更新，请稍后重试';
      notifyListeners();
      return;
    }
    final finish = _updateGuard?.beginActivity('本地图片超分尚未完成');
    try {
      await _runBeforeUpdate();
    } finally {
      finish?.call();
    }
  }

  Future<void> _runBeforeUpdate() async {
    final input = _inputPath;
    if (input == null || _status == SrStatus.running) return;

    _status = SrStatus.running;
    _progress = '准备模型...';
    _progressValue = null;
    _error = null;
    _outputPath = null;
    notifyListeners();

    try {
      await _upscale.prepare();
      final out = await _upscale.execute(
        inputPath: input,
        model: _model,
        onProgress: (line) {
          _progress = line;
          final m = _percentRe.firstMatch(line);
          if (m != null) {
            final pct = double.tryParse(m.group(1)!);
            if (pct != null) {
              _progressValue = (pct / 100).clamp(0.0, 1.0);
            }
          }
          notifyListeners();
        },
      );
      // 校验输出文件确实生成
      if (!await File(out).exists()) {
        throw Exception('未生成输出文件');
      }
      _outputPath = out;
      _status = SrStatus.success;
      _progress = '完成';
      _progressValue = 1.0;
    } catch (e) {
      _status = SrStatus.failed;
      _error = e.toString();
      _progressValue = null;
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    if (_status != SrStatus.running) return;
    await _upscale.cancel();
    _status = SrStatus.idle;
    _progress = '已取消';
    _progressValue = null;
    notifyListeners();
  }

  /// 保存结果到相册，返回是否成功。
  Future<bool> saveToGallery() async {
    final out = _outputPath;
    if (out == null) return false;
    return _saveImage.saveToGallery(out);
  }

  void reset() {
    _inputPath = null;
    _outputPath = null;
    _status = SrStatus.idle;
    _progress = '';
    _progressValue = null;
    _error = null;
    notifyListeners();
  }
}
