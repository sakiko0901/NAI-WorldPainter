class ApiConstants {
  ApiConstants._();

  // 默认 NovelAI Gateway 地址（留空，用户必须自行填写中转站地址）
  static const String defaultBaseUrl = '';

  // API 路径
  static const String chatCompletions = '/v1/chat/completions';
  static const String imageGenerations = '/v1/images/generations';
  static const String imagePreciseReference = '/v1/images/precise-reference';
  static const String imageInpainting = '/v1/images/inpainting';
  static const String imageEdits = '/v1/images/edits';
  static const String imageAnnotate = '/v1/images/annotate';
  static const String imageDirectorDeclutter = '/v1/images/director/declutter';
  static const String imageDirectorBgRemover = '/v1/images/director/bg-remover';
  static const String imageDirectorLineart = '/v1/images/director/lineart';
  static const String imageDirectorSketch = '/v1/images/director/sketch';
  static const String imageDirectorColorize = '/v1/images/director/colorize';
  static const String imageDirectorEmotion = '/v1/images/director/emotion';
  static const String models = '/v1/models';

  // Nano Banana 支持的宽高比（用于 imageConfig.aspectRatio）
  static const List<String> nanoSupportedSizes = [
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
    '3:2',
    '2:3',
  ];

  static const Map<String, String> nanoSizeLabels = {
    '1:1': '1:1 正方形',
    '16:9': '16:9 横版宽屏',
    '9:16': '9:16 竖版',
    '4:3': '4:3 横版',
    '3:4': '3:4 竖版',
    '3:2': '3:2 横版',
    '2:3': '2:3 竖版',
  };

  // Nano Banana 支持的图片尺寸（用于 imageConfig.imageSize）
  static const List<String> nanoImageSizes = ['1K', '2K', '4K'];

  static const Map<String, String> nanoImageSizeLabels = {
    '1K': '1K 标准',
    '2K': '2K 高清',
    '4K': '4K 超清',
  };

  // 支持的画幅
  static const Map<String, Map<String, int>> supportedResolutions = {
    '832x1216': {'width': 832, 'height': 1216},
    '1216x832': {'width': 1216, 'height': 832},
    '1024x1024': {'width': 1024, 'height': 1024},
  };

  static const List<String> ikunSupportedResolutions = [
    '832x1216',
    '1216x832',
    '1024x1024',
    '1024x1536',
    '1536x1024',
    '1472x1472',
    '1088x1920',
    '1920x1088',
  ];

  static const Map<String, String> ikunSizeLabels = {
    '832x1216': '普通 · 纵向 832×1216',
    '1216x832': '普通 · 横向 1216×832',
    '1024x1024': '普通 · 方形 1024×1024',
    '1024x1536': '大图 · 纵向 1024×1536',
    '1536x1024': '大图 · 横向 1536×1024',
    '1472x1472': '大图 · 方形 1472×1472',
    '1088x1920': '壁纸 · 竖屏 1088×1920（超出服务端 1600 限制）',
    '1920x1088': '壁纸 · 横屏 1920×1088（超出服务端 1600 限制）',
  };

  // GPT Image 支持的画幅
  static const List<String> gptSupportedSizes = [
    '1024x1024',
    '1536x1024',
    '1024x1536',
    '2048x2048',
    '2048x1152',
    '3840x2160',
    '2160x3840',
    'auto',
  ];

  static const Map<String, String> gptSizeLabels = {
    '1024x1024': '1024×1024 正方形',
    '1536x1024': '1536×1024 横版',
    '1024x1536': '1024×1536 竖版',
    '2048x2048': '2048×2048 2K正方形',
    '2048x1152': '2048×1152 2K横版',
    '3840x2160': '3840×2160 4K横版',
    '2160x3840': '2160×3840 4K竖版',
    'auto': 'auto 默认',
  };

  // 支持的采样器
  static const List<String> supportedSamplers = [
    'k_euler',
    'k_euler_ancestral',
    'k_dpmpp_2m',
    'k_dpmpp_2s_ancestral',
    'k_dpmpp_sde',
    'ddim',
    'ddim_v3',
    'gans',
  ];

  static const List<String> ikunSupportedSamplers = [
    'k_euler',
    'k_euler_ancestral',
    'k_dpmpp_2m',
    'k_dpmpp_2s_ancestral',
    'k_dpmpp_sde',
    'ddim_v3',
    'gans',
  ];

  // 支持的 noise_schedule
  static const List<String> supportedNoiseSchedules = [
    'native',
    'karras',
    'exponential',
    'polyexponential',
  ];

  static const List<String> ikunSupportedNoiseSchedules = [
    'native',
    'karras',
    'exponential',
  ];

  // 默认参数
  static const double defaultScale = 5.0;
  static const double defaultCfgRescale = 0.0;
  static const String defaultSampler = 'k_euler';
  static const String defaultNoiseSchedule = 'native';
  static const int defaultSteps = 28;
  static const int defaultInpaintingSteps = 23;
  static const String defaultResolution = '832x1216';
}
