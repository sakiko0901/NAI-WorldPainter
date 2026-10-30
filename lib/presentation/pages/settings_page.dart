import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/constants/app_constants.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/domain/entities/novelai_connection.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/api_config_page.dart';
import 'package:nai_huishi/presentation/pages/artist_prompt_manager_page.dart';
import 'package:nai_huishi/presentation/pages/comic_projects_page.dart';
import 'package:nai_huishi/presentation/pages/danbooru_tag_search_page.dart';
import 'package:nai_huishi/presentation/pages/director_tools_page.dart';
import 'package:nai_huishi/presentation/pages/image_tag_page.dart';
import 'package:nai_huishi/presentation/pages/official_upscale_page.dart';
import 'package:nai_huishi/presentation/pages/online_gallery_page.dart';
import 'package:nai_huishi/presentation/pages/theme_appearance_page.dart';
import 'package:nai_huishi/presentation/pages/vibe_encoding_library_page.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/tools/tools_quota_card.dart';
import 'package:nai_huishi/presentation/widgets/frosted_surface.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onNavigateToGenerate;
  final AppearanceMode appearanceMode;
  final ValueChanged<AppearanceMode> onAppearanceChanged;
  final bool frostedGlassEnabled;
  final ValueChanged<bool>? onFrostedGlassChanged;

  const SettingsPage({
    super.key,
    this.onNavigateToGenerate,
    required this.appearanceMode,
    required this.onAppearanceChanged,
    this.frostedGlassEnabled = true,
    this.onFrostedGlassChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsViewModel _vm;
  OfficialNovelAiV5Usage? _v5Usage;
  bool _v5Loading = false;
  String? _v5Error;
  int? _anlas;
  bool _v5TokenConfigured = false;
  bool _settingsLoaded = false;

  bool get _isCustomNovelAiChannel {
    if (!_settingsLoaded) return false;
    final official = _vm.endpoints(ImageProviderType.novelAi).where(
        (endpoint) => endpoint.id == AppConstants.novelAiOfficialEndpointId);
    return official.isNotEmpty &&
        NovelAiConnection.isCustomBaseUrl(official.first.baseUrl);
  }

  @override
  void initState() {
    super.initState();
    _vm = sl<SettingsViewModel>();
    _vm.addListener(_onVmChanged);
    _load();
  }

  Future<void> _load() async {
    await _vm.loadSettings();
    if (!mounted) return;
    setState(() => _settingsLoaded = true);
    await _loadV5Usage();
  }

  /// 汇总官方 V5 体力与 Anlas；缺少 Token 或字段时显示不可用状态。
  Future<void> _loadV5Usage() async {
    if (!_settingsLoaded || _isCustomNovelAiChannel) return;
    if (_v5Loading) return;
    _v5Loading = true;
    if (mounted) {
      setState(() => _v5Error = null);
    }
    try {
      final token = await sl<OfficialNovelAiTokenStore>().read();
      if (!mounted || _isCustomNovelAiChannel) return;
      if (token == null || token.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _v5TokenConfigured = false;
            _v5Usage = null;
            _v5Error = null;
            _anlas = null;
          });
        }
        return;
      }
      if (mounted) setState(() => _v5TokenConfigured = true);
      final usage = await sl<OfficialNovelAiApiService>().fetchV5Usage(token);
      if (mounted && !_isCustomNovelAiChannel) {
        setState(() {
          _v5Usage = usage;
          _anlas = usage?.totalAnlas;
          _v5Error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          // Keep credential and server details out of the tools summary.
          _v5Usage = null;
          _anlas = null;
          _v5Error = '查询失败';
        });
      }
    } finally {
      _v5Loading = false;
      if (mounted) setState(() {});
    }
  }

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {
      if (_isCustomNovelAiChannel) {
        _v5Usage = null;
        _anlas = null;
        _v5TokenConfigured = false;
      }
    });
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(children: [
        const Positioned.fill(child: StudioBackground()),
        SafeArea(
          top: true,
          child: BackdropGroup(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
            children: [
              _SettingsGroup(
                title: 'API 配置',
                children: [
                  _SettingsTile(
                    icon: CupertinoIcons.cube_box,
                    title: 'API 配置',
                    subtitle: 'NovelAI / GPT / Nano Banana 中转站与模型',
                    onTap: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const ApiConfigPage(),
                          ),
                        )
                        .then((_) => _loadV5Usage()),
                  ),
                ],
              ),
              if (!_isCustomNovelAiChannel && _v5TokenConfigured) ...[
                const SizedBox(height: 18),
                _buildV5UsageCard(),
              ],
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '创作扩展',
                children: [
                  _SettingsTile(
                    icon: CupertinoIcons.video_camera_solid,
                    title: '导演工具',
                    subtitle: '去杂物、背景移除、线稿、草图、上色与表情',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const DirectorToolsPage(),
                      ),
                    ),
                  ),
                  _SettingsTile(
                    icon: CupertinoIcons.tag,
                    title: '图片解析',
                    subtitle: 'NAI 元数据提取 / WD-Tagger 智能识别',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => ImageTagPage(
                          onNavigateToGenerate: widget.onNavigateToGenerate,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '素材与提示词',
                children: [
                  _SettingsTile(
                    icon: CupertinoIcons.photo_on_rectangle,
                    title: '在线图库',
                    subtitle: '浏览公开作品与提示词，可复用到创作草稿',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => OnlineGalleryScreen(
                          onNavigateToGenerate: widget.onNavigateToGenerate,
                        ),
                      ),
                    ),
                  ),
                  _SettingsTile(
                    icon: CupertinoIcons.search,
                    title: 'Danbooru 查词',
                    subtitle: '直接搜索真实 Danbooru 标签',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const DanbooruTagSearchPage(),
                      ),
                    ),
                  ),
                  _SettingsTile(
                    icon: CupertinoIcons.person_2_square_stack,
                    title: '画师串管理',
                    subtitle: '分类管理画师、调权重并生成 NAI 画师串',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const ArtistPromptManagerPage(),
                      ),
                    ),
                  ),
                  _SettingsTile(
                    icon: CupertinoIcons.waveform,
                    title: 'Vibe 编码库',
                    subtitle: '管理已保存的氛围编码，复用时跳过重复编码',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const VibeEncodingLibraryPage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '图像处理',
                children: [
                  _SettingsTile(
                    icon: CupertinoIcons.arrow_up_right_square,
                    title: 'Upscale',
                    subtitle: 'NovelAI 官方 2× / 4× 放大',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const OfficialUpscalePage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '主题与外观',
                children: [
                  _SettingsTile(
                    icon: CupertinoIcons.paintbrush_fill,
                    title: '主题与外观',
                    subtitle: '亮色、暗色与毛玻璃效果',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => ThemeAppearancePage(
                          appearanceMode: widget.appearanceMode,
                          onAppearanceChanged: widget.onAppearanceChanged,
                          frostedGlassEnabled: widget.frostedGlassEnabled,
                          onFrostedGlassChanged: widget.onFrostedGlassChanged,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: '更多',
                children: [
                  _SettingsTile(
                    icon: CupertinoIcons.rectangle_3_offgrid,
                    title: '漫画生成',
                    subtitle: '分镜项目、候选主图与本地对白后期',
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => const ComicProjectsPage(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
            ],
          )),
        ),
      ]),
    );
  }

  /// 官方用量卡片；没有配置 Token 或接口未返回字段时显示不可用值。
  Widget _buildV5UsageCard() {
    return ToolsQuotaCard(
      tokenConfigured: _v5TokenConfigured,
      isLoading: _v5Loading,
      hasError: _v5Error != null,
      staminaPercent: _v5Usage?.percent,
      isNegative: _v5Usage?.isNegative ?? false,
      tier: _v5Usage?.tier,
      expiresAt: _v5Usage?.expiresAt,
      anlas: _anlas,
      onRefresh: _loadV5Usage,
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).colorScheme.outlineVariant;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        FrostedSurface(
          radius: 18,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 57),
                    child: Divider(
                      height: 1,
                      thickness: 0.7,
                      color: dividerColor,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 18,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.58),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
