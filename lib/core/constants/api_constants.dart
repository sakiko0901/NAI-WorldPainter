class ApiConstants {
  ApiConstants._();

  // 默认 NovelAI 中转站根地址
  static const String defaultBaseUrl = 'https://novelai.ikun114.top/';

  // NovelAI 官方 API 仅允许使用这些固定 HTTPS 地址。
  static const String officialImageBaseUrl = 'https://image.novelai.net';
  static const String officialApiBaseUrl = 'https://api.novelai.net';
  static const String officialUserData = '/user/data';
  static const String officialGenerateImage = '/ai/generate-image';
  static const String officialEncodeVibe = '/ai/encode-vibe';
  static const String officialAugmentImage = '/ai/augment-image';
  static const String officialUpscale = '/ai/upscale';

  // API 路径
  static const String chatCompletions = '/v1/chat/completions';
  static const String imageGenerations = '/v1/images/generations';
  static const String imageEdits = '/v1/images/edits';
  static const String imageAnnotate = '/v1/images/annotate';
  static const String models = '/v1/models';

  // 7877 保留的 NovelAI 原生扩展路径；常规图片功能使用 /v1/images/generations。
  static const String originGenerateImage = '/origin/ai/generate-image';
  static const String originUpscale = '/origin/ai/upscale';
  static const String originEncodeVibe = '/origin/ai/encode-vibe';
  static const String originAugmentImage = '/origin/ai/augment-image';

  static const List<String> nativeNovelAiModels = [
    'nai-diffusion-4-5-curated',
    'nai-diffusion-4-5-full',
    'nai-diffusion-5-curated',
    'nai-diffusion-5-full',
  ];

  static const List<String> officialNovelAiModels = nativeNovelAiModels;

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
    '1024x1536': {'width': 1024, 'height': 1536},
    '1536x1024': {'width': 1536, 'height': 1024},
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
    '768x1344',
    '1344x768',
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
    '768x1344': '小图 · 纵向 768×1344',
    '1344x768': '小图 · 横向 1344×768',
  };

  // 官方渠道与 7877 渠道支持的画幅。
  static const List<String> officialSupportedResolutions = [
    '832x1216',
    '1216x832',
    '1024x1024',
    '1024x1536',
    '1536x1024',
    '1472x1472',
    '1088x1920',
    '1920x1088',
    '768x1344',
    '1344x768',
  ];

  static const Map<String, String> officialSizeLabels = {
    '832x1216': '普通 · 纵向 832×1216',
    '1216x832': '普通 · 横向 1216×832',
    '1024x1024': '普通 · 方形 1024×1024',
    '1024x1536': '大图 · 纵向 1024×1536',
    '1536x1024': '大图 · 横向 1536×1024',
    '1472x1472': '大图 · 方形 1472×1472',
    '1088x1920': '壁纸 · 竖屏 1088×1920',
    '1920x1088': '壁纸 · 横屏 1920×1088',
    '768x1344': '小图 · 纵向 768×1344（壁纸等比 1MP 内）',
    '1344x768': '小图 · 横向 1344×768（壁纸等比 1MP 内）',
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

  // 新网关文档规定的 NovelAI 采样器。
  static const List<String> supportedSamplers = [
    'k_euler',
    'k_euler_ancestral',
    'k_dpm_2',
    'k_dpm_2_ancestral',
    'k_dpmpp_2m',
    'k_dpmpp_2m_sde',
    'k_dpmpp_2s_ancestral',
    'k_dpmpp_sde',
    'ddim',
  ];

  static const List<String> ikunSupportedSamplers = [
    'k_euler',
    'k_euler_ancestral',
    'k_dpmpp_2s_ancestral',
    'k_dpmpp_2m',
    'k_dpmpp_2m_sde',
    'k_dpmpp_sde',
    'ddim_v3',
  ];

  // 新网关文档规定的噪声调度。
  static const List<String> supportedNoiseSchedules = [
    'karras',
    'exponential',
    'polyexponential',
  ];

  static const List<String> ikunSupportedNoiseSchedules = [
    'native',
    'karras',
    'exponential',
    'polyexponential',
  ];

  // 默认参数
  static const double defaultScale = 5.0;
  static const double defaultCfgRescale = 0.0;
  static const String defaultSampler = 'k_euler_ancestral';
  static const String defaultNoiseSchedule = 'karras';
  static const int defaultSteps = 28;
  static const int defaultInpaintingSteps = 23;
  static const String defaultResolution = '832x1216';
}
