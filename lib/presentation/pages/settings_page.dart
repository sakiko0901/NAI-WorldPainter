import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/api_config_page.dart';
import 'package:nai_huishi/presentation/pages/artist_prompt_manager_page.dart';
import 'package:nai_huishi/presentation/pages/danbooru_tag_search_page.dart';
import 'package:nai_huishi/presentation/pages/director_tools_page.dart';
import 'package:nai_huishi/presentation/pages/image_enhance_page.dart';
import 'package:nai_huishi/presentation/pages/image_tag_page.dart';
import 'package:nai_huishi/presentation/pages/pixiv_upload_page.dart';
import 'package:nai_huishi/presentation/pages/theme_appearance_page.dart';
import 'package:nai_huishi/presentation/pages/vibe_encoding_library_page.dart';
import 'package:nai_huishi/presentation/viewmodels/settings_viewmodel.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback? onNavigateToGenerate;
  final AppearanceMode appearanceMode;
  final ValueChanged<AppearanceMode> onAppearanceChanged;

  const SettingsPage({
    super.key,
    this.onNavigateToGenerate,
    required this.appearanceMode,
    required this.onAppearanceChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SettingsViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = sl<SettingsViewModel>();
    _vm.addListener(_onVmChanged);
    _load();
  }

  Future<void> _load() async {
    await _vm.loadSettings();
    if (mounted) setState(() {});
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 14),
              child: Text(
                '更多',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            _SettingsGroup(
              title: '图像 API 设置',
              children: [
                _SettingsTile(
                  icon: CupertinoIcons.cube_box,
                  title: 'API 配置',
                  subtitle: 'NovelAI / GPT / Nano Banana 中转站与模型',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ApiConfigPage()),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            _SettingsGroup(
              title: '更多功能',
              children: [
                _SettingsTile(
                  icon: CupertinoIcons.search,
                  title: 'Danbooru 查词',
                  subtitle: '直接搜索真实 Danbooru 标签',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                        builder: (_) => const DanbooruTagSearchPage()),
                  ),
                ),
                _SettingsTile(
                  icon: CupertinoIcons.video_camera_solid,
                  title: '导演工具',
                  subtitle: '去杂物、背景移除、线稿、草图、上色与表情',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                        builder: (_) => const DirectorToolsPage()),
                  ),
                ),
                _SettingsTile(
                  icon: CupertinoIcons.person_2_square_stack,
                  title: '画师串管理',
                  subtitle: '分类管理画师、调权重并生成 NAI 画师串',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                        builder: (_) => const ArtistPromptManagerPage()),
                  ),
                ),
                _SettingsTile(
                  icon: CupertinoIcons.wand_stars,
                  title: '图像增强',
                  subtitle: '本地超分放大，Real-ESRGAN / RealCUGAN',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                        builder: (_) => const ImageEnhancePage()),
                  ),
                ),
                _SettingsTile(
                  icon: CupertinoIcons.waveform,
                  title: 'Vibe 编码库',
                  subtitle: '管理已保存的氛围编码，复用时跳过重复编码',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                        builder: (_) => const VibeEncodingLibraryPage()),
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
                            )),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            _SettingsGroup(
              title: 'Pixiv 投稿',
              children: [
                _SettingsTile(
                  icon: CupertinoIcons.cloud_upload,
                  title: '上传到 Pixiv',
                  subtitle: '把作品发布到 Pixiv，自动填充标题 / 标签 / 描述',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(builder: (_) => const PixivUploadPage()),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            _SettingsGroup(
              title: '主题与外观',
              children: [
                _SettingsTile(
                  icon: CupertinoIcons.paintbrush_fill,
                  title: '主题与外观',
                  subtitle: '亮色、暗色与咖啡纸主题',
                  onTap: () => Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (_) => ThemeAppearancePage(
                        appearanceMode: widget.appearanceMode,
                        onAppearanceChanged: widget.onAppearanceChanged,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.black.withValues(alpha: 0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C21) : Colors.white,
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 86),
                      child: Divider(
                          height: 1, thickness: 0.7, color: dividerColor),
                    ),
                ],
              ],
            ),
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
                child: Icon(icon,
                    size: 20, color: Theme.of(context).colorScheme.primary),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
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
