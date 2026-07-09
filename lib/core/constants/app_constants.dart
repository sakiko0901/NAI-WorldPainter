class AppConstants {
  AppConstants._();

  static const String appName = 'nai 绘世';
  static const String appNameEn = 'NAI Huishi';

  // 数据库
  static const String dbName = 'nai_huishi.db';
  static const int dbVersion = 9;

  // 本地存储
  static const String imagesDirName = 'generated_images';
  static const String stylePresetsDirName = 'style_presets';
  static const String artistPromptsDirName = 'artist_prompts';

  // 设置 key
  static const String keyApiKey = 'api_key';
  static const String keyBaseUrl = 'base_url';
  static const String keyDefaultModel = 'default_model';
  static const String keyDefaultResolution = 'default_resolution';
  static const String keyDefaultSampler = 'default_sampler';
  static const String keyDefaultScale = 'default_scale';
  static const String keyDefaultCfgRescale = 'default_cfg_rescale';
  static const String keyDefaultNoiseSchedule = 'default_noise_schedule';

  // 默认提示词（Agent 设置页配置，每次生图时自动拼接到 prompt 前面）
  static const String keyDefaultStyleWords = 'default_style_words';
  static const String keyPromptDraft = 'prompt_draft';
  static const String keyNegativePromptDraft = 'negative_prompt_draft';
  static const String keySelectedModelDraft = 'selected_model_draft';
  static const String keySelectedResolutionDraft = 'selected_resolution_draft';
  static const String keySelectedSamplerDraft = 'selected_sampler_draft';
  static const String keySelectedNoiseScheduleDraft = 'selected_noise_schedule_draft';
  static const String keyScaleDraft = 'scale_draft';
  static const String keyCfgRescaleDraft = 'cfg_rescale_draft';
  static const String keyCharactersDraft = 'characters_draft';
  static const String keyInpaintPromptDraft = 'inpaint_prompt_draft';
  static const String keyInpaintNegativePromptDraft = 'inpaint_negative_prompt_draft';

  // LLM 提示词辅助（旧单配置，仅用于迁移，迁移后不再读取）
  static const String keyLlmApiKey = 'llm_api_key';
  static const String keyLlmBaseUrl = 'llm_base_url';
  static const String keyLlmModel = 'llm_model';
  static const String keyLlmSystemPrompt = 'llm_system_prompt';
  static const String keyLlmActiveSessionId = 'llm_active_session_id';

  // LLM 供应商列表（List<LlmProvider> 的 JSON 字符串）
  static const String keyLlmProviders = 'llm_providers_json';

  // LLM 角色绑定（main/vision 各存 LlmRoleBinding JSON）
  static const String keyLlmRoleBindingMain = 'llm_role_binding_main';
  static const String keyLlmRoleBindingVision = 'llm_role_binding_vision';

  static const String keyLlmContextLimit = 'llm_context_limit'; // int

  // 知识库
  static const String keyNsfwBookPath = 'nsfw_book_path';

  // 联网搜索（手动开关，跨会话持久化）
  static const String keyWebSearchEnabled = 'llm_web_search_enabled';

  // Danbooru 智能校准
  static const String keyDanbooruCalibrationEnabled = 'danbooru_calibration_enabled';
  static const String keyDanbooruBaseUrl = 'danbooru_base_url';

  static const int defaultLlmContextLimit = 20;

  // 默认 LLM 系统提示词（用户可在聊天面板齿轮里编辑）
  static const String defaultLlmSystemPrompt =
      '你是 NovelAI 提示词辅助 Agent。你的核心使命是辅助用户进行 NovelAI 创作：编排英文 tag 提示词、修改现有提示词框、检索 Danbooru 真实 tag、查询本地记忆库、生成/放大/保存/上传图片。\n'
      '\n'
      '## 模型角色分工\n'
      '- **主模型（你）**：负责 Agent 循环、工具调用、最终回复。\n'
      '- **识图模型**：用户上传图片时由系统自动调用（vision 多模态），理解图片内容。\n'
      '\n'
      '## 工具使用时机\n'
      '- `read_current_prompts`：当用户说"在现有基础上改"、"加个 XX 效果"、"换成夜晚"等涉及修改现有提示词的请求时，先调用此工具读取 4 个提示词框的当前内容（positive/negative/inpaint_positive/inpaint_negative）。\n'
      '- `write_prompt`：编排好新提示词后，调用此工具写入对应框。mode=append 用于追加（默认），mode=replace 用于覆盖。target 取值：positive / negative / inpaint_positive / inpaint_negative。新对话开始时若用户没说"在现有基础上改"，不要主动调 read_current_prompts——提示词框可能是上次生图遗留的。\n'
      '- `web_search`：用户问实时信息、角色最新设定、不确定的事实时调用。\n'
      '- `search_danbooru`：用户提及角色/画风/场景，需要找 Danbooru 真实 tag 时调用。返回真实存在的 tag 池，**不要凭空创造 tag**。单次检索返回最多 30 个 tag，足够覆盖一个角色的全部常见特征（发色/瞳色/服装等），不需要为每个细节单独搜。只有切换到不同角色/不同场景/不同画风时才需要再次调用。\n'
      '- `get_memories`：查询本地学习记忆库。用户曾纠正过的"触发词→正确内容"映射会命中。优先级高于 Danbooru 与模型常识。\n'
      '- `save_memory`：用户明确纠正人名、角色特征、画风知识时调用。例如用户说"记住：纳西妲是青绿眼"。\n'
      '- `generate_image` / `upscale_image` / `save_image` / `upload_to_pixiv`：用户明确要求时调用，会弹窗让用户确认。\n'
      '- `remove_character`：删除指定多角色格子（参数 index，1-based）。当用户不再需要某个角色、要从多角色场景改成单角色、或多角色格过多导致生图失败时调用。\n'
      '- `clear_characters`：清空全部多角色格子。当从多角色切换到单角色场景时调用（不影响 positive/negative 框）。\n'
      '\n'
      '### 局部重绘框保护\n'
      '- inpaint_positive 和 inpaint_negative 是"局部重绘"专用框，仅当用户明确要求修改局部/重绘/修图时才能写入。\n'
      '- 文生图模式下，这两个框是上次遗留内容、不会被使用——read_current_prompts 会标注"当前非局部重绘模式"，不要被遗留内容误导。\n'
      '- 非重绘模式下调写 inpaint 框会被工具拒绝并返回错误，此时应改写 positive/negative。\n'
      '\n'
      '## NovelAI 标签语法规范（编排提示词时必须遵循）\n'
      '\n'
      '### 一、基础语法\n'
      '- 标签语言：必须使用英文。\n'
      '- 分隔符：标签间使用半角逗号 `,` 分隔。\n'
      '- 权重符号：`{tag}` 增强（1.1倍），`[tag]` 削弱（0.9倍），`tag1|tag2` 混合。\n'
      '- 数字权重：`1.5::tag::`（结尾必须带双冒号闭合）。权重范围 0-8，精确到 0.1。常用区间 1-2。\n'
      '- 越靠前的单词权重越大：主要描述靠前，次要描述靠后。\n'
      '\n'
      '### 二、提示词逻辑排序（优先级从高到低）\n'
      '画质词（masterpiece, best quality, amazing quality, very aesthetic, absurdres）> 风格/艺术家 > 核心主体 > 特征描述（发色→发型→瞳色→表情）> 服装与配饰 > 姿势 > 物品 > 环境与背景 > 光影与构图 > 整体风格。\n'
      '\n'
      '### 三、特定角色 tag 规范\n'
      '- 指定作品/角色：`角色名 (作品名)`，例如 `Castorice (honkai: star rail)`。角色名与作品名之间必须用空格分开。\n'
      '- 指定皮肤/变体：`角色名_(皮肤名)_(作品名)`，例如 `Hu_Tao_(Cherries_Snow-Laden)_(genshin_impact)`。\n'
      '- 游戏/CG 风格：`1.2::honkai: star rail (game cg)::`。\n'
      '\n'
      '### 四、负面提示词\n'
      '- 只在明确需要排除某样东西时才加负面 tag，不要堆砌。\n'
      '- 基础负面：`lowres, worst quality, bad quality, jpeg artifacts, bad anatomy, extra digits, missing fingers, signature, watermark, username, error, fewer, scan, sketch, lineart, rough, text, cropped, blurry, monochrome, grayscale`。\n'
      '\n'
      '### 五、多角色与互动\n'
      '- 2 人以上时，**必须**用 write_prompt 工具写入 character_1、character_2 等独立框，每角色单独一个 prompt 框，防止外貌动作混淆。\n'
      '- 多角色 prompt 不要重复 positive 里的通用画质词（masterpiece 等），只写该角色独有特征（发色→发型→瞳色→表情→服装→动作）。\n'
      '- 互动标签：`source#hugging`（施动方）、`target#hugging`（受动方）、`mutual#holding hands`（相互）。source/target 必须成对出现。\n'
      '- 第一人称视角用 `pov`（男/通用）或 `female pov`（女）。\n'
      '\n'
      '### 六、画面文字\n'
      'NovelAI 支持在图像中嵌入文字：主提示词区域空一行后，独立一行输入 `TEXT: 想要显示的文字`。可配合 `speech bubble` 等标签做漫画效果。\n'
      '\n'
      '### 七、避坑\n'
      '- 避免矛盾描述（如 day 与 night 同现）。\n'
      '- 强视角（特写）时移除与视角不符的身体描述。\n'
      '- 标签名以数字结尾（如 `z1`）时，必须在其后加逗号或空格再接双冒号：`(z1,::)`。\n'
      '\n'
      '## 输出格式\n'
      '\n'
      '调 `write_prompt` 工具写入对应框后，最终回复用普通文本段落简要回应用户即可（如"已写入正向框，主角：纳西妲，背景：星空"）。**不要再使用 ``` 代码块格式输出提示词**——提示词已经写入框内，用户可直接看到，无需双保险。\n'
      '\n'
      '如需在回复里展示编排的 tag，用普通段落文本或引号包裹，不要用 ``` 围栏。\n'
      '\n'
      '多角色场景：用"角色 1：xxx / 角色 2：xxx / 通用底模：xxx / 负向：xxx"普通文本罗列，每个角色单起一行，不要用代码块。\n'
      '\n'
      '## 行为约束\n'
      '- NSFW 题材被允许，质量词前加 `nsfw,` 前缀。\n'
      '- 用户问"画 XXX"时：先 `search_danbooru` 找真实 tag，再 `write_prompt`（positive, append）。\n'
      '- 用户问"在现有基础上改 XXX"时：**必须先 `read_current_prompts`** 读取 4 个框当前内容，再 `write_prompt`。禁止跳过 read 直接 append。\n'
      '- 修改/替换/重排现有提示词时，用 mode=replace，但 replace 前必须 read，并把 read 到的旧内容做精细修改后整体写回——不要丢失用户已有 tag。\n'
      '- 添加新元素到现有提示词尾部时，用 mode=append（自动去重，但仍建议先 read 确认）。\n'
      '- 用户明确纠正人名/特征/画风时：调 `save_memory`，然后回复确认。\n'
      '- 不要在 tool 调用之间凭空想象 tag，所有 tag 必须来自 Danbooru 检索结果或用户本地记忆。\n'
      '- 多角色场景（2 人及以上）**禁止单纯把全部特征写入 positive**，必须按角色拆分到 character_1、character_2…；positive 只放通用画质词与画风词，角色独有特征（角色名、发色、瞳色、服装、动作）一律进 character_N。\n';

  // 图像 API 供应商配置
  static const String keyImageProviderNovelAiBaseUrl = 'image_provider_novelai_base_url';
  static const String keyImageProviderNovelAiApiKey = 'image_provider_novelai_api_key';
  static const String keyImageProviderNovelAiModel = 'image_provider_novelai_model';
  static const String keyImageProviderGptBaseUrl = 'image_provider_gpt_base_url';
  static const String keyImageProviderGptApiKey = 'image_provider_gpt_api_key';
  static const String keyImageProviderGptModel = 'image_provider_gpt_model';
  static const String keyImageProviderNanoBaseUrl = 'image_provider_nano_base_url';
  static const String keyImageProviderNanoApiKey = 'image_provider_nano_api_key';
  static const String keyImageProviderNanoModel = 'image_provider_nano_model';

  // 图像 API 供应商配置 — v2 多中转站结构
  static const String keyImageProviderNovelAiEndpoints = 'image_provider_novelai_endpoints';
  static const String keyImageProviderNovelAiActiveEndpointId = 'image_provider_novelai_active_endpoint_id';
  static const String keyImageProviderNovelAiActiveModel = 'image_provider_novelai_active_model_v2';
  static const String keyImageProviderGptEndpoints = 'image_provider_gpt_endpoints';
  static const String keyImageProviderGptActiveEndpointId = 'image_provider_gpt_active_endpoint_id';
  static const String keyImageProviderGptActiveModel = 'image_provider_gpt_active_model_v2';
  static const String keyImageProviderNanoEndpoints = 'image_provider_nano_endpoints';
  static const String keyImageProviderNanoActiveEndpointId = 'image_provider_nano_active_endpoint_id';
  static const String keyImageProviderNanoActiveModel = 'image_provider_nano_active_model_v2';

  // 批量生成
  static const String keyBatchCount = 'batch_count_draft';

  // 图片解析缓存
  static const String keyImageTagImagePath = 'image_tag_image_path';
  static const String keyImageTagMode = 'image_tag_mode'; // 0=nai, 1=wdTagger
  static const String keyImageTagResultJson = 'image_tag_result_json';
  static const String keyImageTagWdModel = 'image_tag_wd_model'; // wd-tagger 模型 repo
  static const String keyImageTagGeneralThreshold = 'image_tag_general_threshold';
  static const String keyImageTagCharacterThreshold = 'image_tag_character_threshold';

  // 任务状态
  static const String taskPending = 'pending';
  static const String taskGenerating = 'generating';
  static const String taskSuccess = 'success';
  static const String taskFailed = 'failed';

  // 预设分类
  static const List<String> presetCategories = [
    '二次元',
    '写实',
    '角色',
    '风景',
    'Furry',
    '其他',
  ];

  // Prompt 模板分类
  static const List<String> promptTemplateCategories = [
    '角色',
    '场景',
    '风格',
    '质量',
    '姿势',
    '其他',
  ];

  // Pixiv 上传
  static const String keyPixivCookie = 'pixiv_cookie';
  static const String keyPixivCsrfToken = 'pixiv_csrf_token';
  static const String keyPixivProxy = 'pixiv_proxy';
  static const String keyPixivCaptionPrefix = 'pixiv_caption_prefix';
  static const String keyPixivDefaultTags = 'pixiv_default_tags';
  static const String keyPixivR18Default = 'pixiv_r18_default';
  static const String keyPixivAllowTagEdit = 'pixiv_allow_tag_edit';
  static const String keyPixivStripMetadata = 'pixiv_strip_metadata';
  static const String keyPixivCooldownMinutes = 'pixiv_cooldown_minutes';
  static const String keyPixivRepTagsPercent = 'pixiv_rep_tags_percent';
  static const String keyPixivRepTagsFill = 'pixiv_rep_tags_fill';
  static const String keyPixivCustomCharacters = 'pixiv_custom_characters';
  static const String keyPixivCustomSurroundings = 'pixiv_custom_surroundings';
  static const String keyPixivJunkText = 'pixiv_junk_text';
  static const String keyPixivSuggestTagsEnabled = 'pixiv_suggest_tags_enabled';

  // Pixiv 默认值
  static const String defaultPixivCaptionPrefix = '由 nai 绘世 生成';
  static const List<String> defaultPixivTags = ['女の子', 'NovelAI'];
  static const int defaultPixivCooldownMinutes = 15;
  static const double defaultPixivRepTagsPercent = 1.0;
  static const String defaultPixivRepTagsFill = '杂鱼~';
  static const String defaultPixivJunkText = '';
}
