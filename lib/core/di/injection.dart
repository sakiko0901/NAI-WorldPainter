import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nai_huishi/data/datasources/local/database_helper.dart';
import 'package:nai_huishi/data/datasources/local/llm_chat_local_datasource.dart';
import 'package:nai_huishi/data/datasources/local/settings_local_datasource.dart';
import 'package:nai_huishi/data/datasources/remote/llm_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/novelai_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/gpt_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/nano_banana_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/bing_search_service.dart';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/data/datasources/remote/duckduckgo_search_service.dart';
import 'package:nai_huishi/data/datasources/remote/wd_tagger_api_service.dart';
import 'package:nai_huishi/data/repositories/artist_prompt_repository_impl.dart';
import 'package:nai_huishi/data/repositories/generation_repository_impl.dart';
import 'package:nai_huishi/data/repositories/history_repository_impl.dart';
import 'package:nai_huishi/data/repositories/llm_chat_repository_impl.dart';
import 'package:nai_huishi/data/repositories/preset_repository_impl.dart';
import 'package:nai_huishi/data/repositories/prompt_memory_repository_impl.dart';
import 'package:nai_huishi/data/repositories/prompt_template_repository_impl.dart';
import 'package:nai_huishi/data/repositories/settings_repository_impl.dart';
import 'package:nai_huishi/data/repositories/style_preset_repository_impl.dart';
import 'package:nai_huishi/domain/agents/agent_loop.dart';
import 'package:nai_huishi/domain/agents/tool_registry.dart';
import 'package:nai_huishi/domain/agents/tools/get_memories_tool.dart';
import 'package:nai_huishi/domain/agents/tools/save_memory_tool.dart';
import 'package:nai_huishi/domain/agents/tools/read_current_prompts_tool.dart';
import 'package:nai_huishi/domain/agents/tools/remove_character_tool.dart';
import 'package:nai_huishi/domain/agents/tools/write_prompt_tool.dart';
import 'package:nai_huishi/domain/agents/tools/web_search_tool.dart';
import 'package:nai_huishi/domain/agents/tools/search_danbooru_tool.dart';
import 'package:nai_huishi/domain/agents/tools/generate_image_tool.dart';
import 'package:nai_huishi/domain/agents/tools/upscale_image_tool.dart';
import 'package:nai_huishi/domain/agents/tools/save_image_tool.dart';
import 'package:nai_huishi/domain/agents/tools/upload_to_pixiv_tool.dart';
import 'package:nai_huishi/domain/repositories/artist_prompt_repository.dart';
import 'package:nai_huishi/domain/repositories/generation_repository.dart';
import 'package:nai_huishi/domain/repositories/history_repository.dart';
import 'package:nai_huishi/domain/repositories/llm_chat_repository.dart';
import 'package:nai_huishi/domain/repositories/preset_repository.dart';
import 'package:nai_huishi/domain/repositories/prompt_memory_repository.dart';
import 'package:nai_huishi/domain/repositories/prompt_template_repository.dart';
import 'package:nai_huishi/domain/repositories/settings_repository.dart';
import 'package:nai_huishi/domain/repositories/style_preset_repository.dart';
import 'package:nai_huishi/domain/usecases/manage_artist_prompts.dart';
import 'package:nai_huishi/domain/usecases/generate_image.dart';
import 'package:nai_huishi/domain/usecases/get_history.dart';
import 'package:nai_huishi/domain/usecases/manage_llm_chat.dart';
import 'package:nai_huishi/domain/usecases/manage_presets.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_memories.dart';
import 'package:nai_huishi/domain/usecases/manage_prompt_templates.dart';
import 'package:nai_huishi/domain/usecases/manage_settings.dart';
import 'package:nai_huishi/domain/usecases/manage_style_presets.dart';
import 'package:nai_huishi/domain/usecases/save_image.dart';
import 'package:nai_huishi/domain/usecases/calibrate_with_danbooru.dart';
import 'package:nai_huishi/domain/usecases/extract_keywords.dart';
import 'package:nai_huishi/domain/usecases/search_danbooru_tags.dart';
import 'package:nai_huishi/domain/usecases/upscale_image.dart';
import 'package:nai_huishi/domain/repositories/super_resolution_repository.dart';
import 'package:nai_huishi/data/datasources/super_resolution_channel.dart';
import 'package:nai_huishi/data/repositories/super_resolution_repository_impl.dart';
import 'package:nai_huishi/core/queue/generation_queue.dart';
import 'package:nai_huishi/core/network/robust_http_adapter.dart';
import 'package:nai_huishi/presentation/viewmodels/artist_prompt_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/history_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/preset_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/prompt_memory_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/prompt_template_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/style_preset_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/super_resolution_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/image_tag_viewmodel.dart';
import 'package:nai_huishi/domain/usecases/analyze_image_tags.dart';

// Pixiv
import 'package:nai_huishi/core/services/pixiv_upload_queue_service.dart';
import 'package:nai_huishi/data/datasources/local/pixiv_image_cloaker.dart';
import 'package:nai_huishi/data/datasources/local/pixiv_settings_local_datasource.dart';
import 'package:nai_huishi/data/datasources/local/pixiv_title_generator.dart';
import 'package:nai_huishi/data/datasources/remote/pixiv_api_service.dart';
import 'package:nai_huishi/data/repositories/pixiv_settings_repository_impl.dart';
import 'package:nai_huishi/data/repositories/pixiv_upload_repository_impl.dart';
import 'package:nai_huishi/domain/repositories/pixiv_settings_repository.dart';
import 'package:nai_huishi/domain/repositories/pixiv_upload_repository.dart';
import 'package:nai_huishi/domain/usecases/manage_pixiv_settings.dart';
import 'package:nai_huishi/domain/usecases/suggest_pixiv_tags.dart';
import 'package:nai_huishi/domain/usecases/upload_to_pixiv.dart';
import 'package:nai_huishi/presentation/viewmodels/pixiv_queue_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/pixiv_settings_viewmodel.dart';
import 'package:nai_huishi/presentation/viewmodels/pixiv_upload_viewmodel.dart';

final sl = GetIt.instance;

Future<void> configureDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  sl.registerSingleton<SharedPreferences>(prefs);

  final db = await DatabaseHelper.instance.database;
  sl.registerSingleton<Database>(db);

  sl.registerSingleton<Dio>(createRobustDio());

  sl.registerSingleton<SettingsLocalDatasource>(SettingsLocalDatasource(sl<SharedPreferences>()));
  sl.registerSingleton<NovelAiApiService>(NovelAiApiService(sl<Dio>()));
  sl.registerSingleton<GptApiService>(GptApiService(sl<Dio>()));
  sl.registerSingleton<NanoBananaApiService>(NanoBananaApiService(sl<Dio>()));
  sl.registerSingleton<LlmApiService>(LlmApiService(sl<Dio>()));
  sl.registerSingleton<BingSearchService>(BingSearchService());
  sl.registerSingleton<DanbooruApiService>(DanbooruApiService());
  sl.registerSingleton<DuckDuckGoSearchService>(DuckDuckGoSearchService(sl<Dio>()));
  sl.registerSingleton<WdTaggerApiService>(WdTaggerApiService(sl<Dio>()));
  sl.registerSingleton<LlmChatLocalDatasource>(LlmChatLocalDatasource(sl<Database>()));

  // 旧 3 角色 9 key + 旧单配置 → 供应商+绑定 迁移
  sl<SettingsLocalDatasource>().migrateLegacyLlm3RoleToProvider();

  final settingsRepo = SettingsRepositoryImpl(sl<SettingsLocalDatasource>());
  settingsRepo.setApiService(sl<NovelAiApiService>());
  sl.registerSingleton<SettingsRepository>(settingsRepo);

  sl.registerSingleton<GenerationRepository>(GenerationRepositoryImpl(
    apiService: sl<NovelAiApiService>(),
    gptApiService: sl<GptApiService>(),
    nanoApiService: sl<NanoBananaApiService>(),
    settingsRepo: sl<SettingsRepository>(),
  ));
  sl.registerSingleton<HistoryRepository>(HistoryRepositoryImpl(sl<Database>()));
  sl.registerSingleton<PresetRepository>(PresetRepositoryImpl(sl<Database>()));
  sl.registerSingleton<PromptMemoryRepository>(PromptMemoryRepositoryImpl(sl<Database>()));
  sl.registerSingleton<PromptTemplateRepository>(PromptTemplateRepositoryImpl(sl<Database>()));
  sl.registerSingleton<StylePresetRepository>(StylePresetRepositoryImpl(sl<Database>()));
  sl.registerSingleton<ArtistPromptRepository>(ArtistPromptRepositoryImpl(sl<Database>()));
  sl.registerSingleton<LlmChatRepository>(LlmChatRepositoryImpl(
    local: sl<LlmChatLocalDatasource>(),
    api: sl<LlmApiService>(),
  ));

  sl.registerSingleton<GenerationQueue>(GenerationQueue(
    sl<GenerationRepository>(),
    sl<HistoryRepository>(),
  ));

  sl.registerSingleton<GenerateImageUseCase>(GenerateImageUseCase(
    sl<HistoryRepository>(),
  ));
  sl.registerSingleton<GetHistoryUseCase>(GetHistoryUseCase(sl<HistoryRepository>()));
  sl.registerSingleton<ManagePresetsUseCase>(ManagePresetsUseCase(sl<PresetRepository>()));
  sl.registerSingleton<ManagePromptMemoriesUseCase>(ManagePromptMemoriesUseCase(sl<PromptMemoryRepository>()));
  sl.registerSingleton<ManagePromptTemplatesUseCase>(ManagePromptTemplatesUseCase(sl<PromptTemplateRepository>()));
  sl.registerSingleton<ManageSettingsUseCase>(ManageSettingsUseCase(sl<SettingsRepository>()));
  sl.registerSingleton<ManageStylePresetsUseCase>(ManageStylePresetsUseCase(sl<StylePresetRepository>()));
  sl.registerSingleton<ManageArtistPromptsUseCase>(ManageArtistPromptsUseCase(sl<ArtistPromptRepository>()));
  sl.registerSingleton<ManageLlmChatUseCase>(ManageLlmChatUseCase(sl<LlmChatRepository>()));
  sl.registerSingleton<SaveImageUseCase>(SaveImageUseCase(sl<HistoryRepository>()));
  sl.registerSingleton<CalibrateWithDanbooruUseCase>(
      CalibrateWithDanbooruUseCase(sl<DanbooruApiService>()));
  sl.registerSingleton<ExtractKeywordsUseCase>(
      ExtractKeywordsUseCase(sl<LlmApiService>()));
  sl.registerSingleton<SearchDanbooruTagsUseCase>(
      SearchDanbooruTagsUseCase(sl<DanbooruApiService>()));

  // 图片超分
  sl.registerSingleton<SuperResolutionChannel>(SuperResolutionChannel());
  sl.registerSingleton<SuperResolutionRepository>(
      SuperResolutionRepositoryImpl(sl<SuperResolutionChannel>()));
  sl.registerSingleton<UpscaleImageUseCase>(
      UpscaleImageUseCase(sl<SuperResolutionRepository>()));

  sl.registerSingleton<AnalyzeImageTagsUseCase>(AnalyzeImageTagsUseCase(
    remote: sl<WdTaggerApiService>(),
  ));

  // ── Pixiv 投稿 UseCase（Tool 需要，提前注册） ──
  sl.registerSingleton<PixivSettingsLocalDatasource>(
      PixivSettingsLocalDatasource(sl<SharedPreferences>()));
  sl.registerSingleton<PixivApiService>(PixivApiService());
  sl.registerSingleton<PixivImageCloaker>(PixivImageCloaker());
  sl.registerSingleton<PixivTitleGenerator>(
      PixivTitleGenerator(sl<PixivSettingsLocalDatasource>()));
  sl.registerSingleton<PixivSettingsRepository>(
      PixivSettingsRepositoryImpl(sl<PixivSettingsLocalDatasource>()));
  sl.registerSingleton<PixivUploadRepository>(PixivUploadRepositoryImpl(
      sl<PixivApiService>(), sl<PixivSettingsLocalDatasource>()));
  sl.registerSingleton<ManagePixivSettingsUseCase>(
      ManagePixivSettingsUseCase(sl<PixivSettingsRepository>()));
  sl.registerSingleton<SuggestPixivTagsUseCase>(
      SuggestPixivTagsUseCase(sl<PixivUploadRepository>()));
  sl.registerSingleton<UploadToPixivUseCase>(
      UploadToPixivUseCase(sl<PixivUploadRepository>()));
  sl.registerSingleton<PixivUploadQueueService>(PixivUploadQueueService(
    sl<PixivApiService>(),
    sl<PixivSettingsLocalDatasource>(),
    sl<PixivImageCloaker>(),
  ));

  // ── GenerationViewModel 注册为 lazySingleton，便于 Tool 复用同一实例 ──
  sl.registerLazySingleton<GenerationViewModel>(() => GenerationViewModel(
    generateImage: sl<GenerateImageUseCase>(),
    manageSettings: sl<ManageSettingsUseCase>(),
    saveImage: sl<SaveImageUseCase>(),
    queue: sl<GenerationQueue>(),
  ));
  sl.registerFactory<SuperResolutionViewModel>(() => SuperResolutionViewModel(
    sl<UpscaleImageUseCase>(),
    sl<SaveImageUseCase>(),
  ));
  sl.registerLazySingleton<HistoryViewModel>(() => HistoryViewModel(sl<GetHistoryUseCase>(), sl<GenerationQueue>()));
  sl.registerFactory<PresetViewModel>(() => PresetViewModel(sl<ManagePresetsUseCase>()));
  sl.registerFactory<PromptMemoryViewModel>(() => PromptMemoryViewModel(sl<ManagePromptMemoriesUseCase>()));
  sl.registerFactory<PromptTemplateViewModel>(() => PromptTemplateViewModel(sl<ManagePromptTemplatesUseCase>()));
  sl.registerLazySingleton<SettingsViewModel>(() => SettingsViewModel(sl<ManageSettingsUseCase>()));
  sl.registerFactory<StylePresetViewModel>(() => StylePresetViewModel(sl<ManageStylePresetsUseCase>()));
  sl.registerFactory<ArtistPromptViewModel>(() => ArtistPromptViewModel(sl<ManageArtistPromptsUseCase>()));
  // 图片解析
  sl.registerFactory<ImageTagViewModel>(() => ImageTagViewModel(
    useCase: sl<AnalyzeImageTagsUseCase>(),
  ));

  // ── Agent 工具与循环 ──
  final toolRegistry = ToolRegistry()
    ..register(GetMemoriesTool(sl<ManagePromptMemoriesUseCase>()))
    ..register(SaveMemoryTool(sl<ManagePromptMemoriesUseCase>()))
    ..register(ReadCurrentPromptsTool(sl<GenerationViewModel>()))
    ..register(WritePromptTool(sl<GenerationViewModel>()))
    ..register(RemoveCharacterTool(sl<GenerationViewModel>()))
    ..register(ClearCharactersTool(sl<GenerationViewModel>()))
    ..register(WebSearchTool(sl<DuckDuckGoSearchService>()))
    ..register(SearchDanbooruTool(sl<DanbooruApiService>()))
    ..register(GenerateImageTool(sl<GenerationViewModel>()))
    ..register(UpscaleImageTool(sl<UpscaleImageUseCase>()))
    ..register(SaveImageTool(sl<SaveImageUseCase>(), sl<HistoryRepository>()))
    ..register(UploadToPixivTool(sl<UploadToPixivUseCase>()));
  sl.registerSingleton<ToolRegistry>(toolRegistry);

  // AgentLoop 注册为 factory：每次 sendUserMessage 时创建新实例并传入本次的 onRequireConfirmation 回调
  sl.registerFactory<AgentLoop>(() => AgentLoop(
    api: sl<LlmApiService>(),
    registry: sl<ToolRegistry>(),
  ));

  sl.registerLazySingleton<LlmChatViewModel>(() {
    // 设置 ViewModel 静态依赖
    LlmChatViewModel.apiServiceSingleton = sl<LlmApiService>();
    LlmChatViewModel.toolRegistrySingleton = sl<ToolRegistry>();
    return LlmChatViewModel(
      manageChat: sl<ManageLlmChatUseCase>(),
      manageSettings: sl<ManageSettingsUseCase>(),
      memories: sl<ManagePromptMemoriesUseCase>(),
      agentLoopFactory: () => sl<AgentLoop>(),
      genVm: sl<GenerationViewModel>(),
      analyzeImageTags: sl<AnalyzeImageTagsUseCase>(),
    );
  });

  // ── Pixiv 投稿 UI ViewModel ──
  sl.registerFactory<PixivSettingsViewModel>(
      () => PixivSettingsViewModel(sl<ManagePixivSettingsUseCase>()));
  sl.registerFactory<PixivUploadViewModel>(() => PixivUploadViewModel(
        upload: sl<UploadToPixivUseCase>(),
        suggest: sl<SuggestPixivTagsUseCase>(),
        settingsUC: sl<ManagePixivSettingsUseCase>(),
        titleGen: sl<PixivTitleGenerator>(),
        queue: sl<PixivUploadQueueService>(),
      ));
  sl.registerFactory<PixivQueueViewModel>(
      () => PixivQueueViewModel(sl<PixivUploadQueueService>()));
}
