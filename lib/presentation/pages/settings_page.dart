import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/official_novelai_token_store.dart';
import 'package:nai_huishi/data/datasources/remote/official_novelai_api_service.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/pages/api_config_page.dart';
import 'package:nai_huishi/presentation/pages/artist_prompt_manager_page.dart';
import 'package:nai_huishi/presentation/pages/comic_projects_page.dart';
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
  OfficialNovelAiV5Usage? _v5Usage;
  bool _v5Loading = false;
  String? _v5Error;
  int? _anlas;

  @override
  void initState() {
    super.initState();
    _vm = sl<SettingsViewModel>();
    _vm.addListener(_onVmChanged);
    _load();
    _loadV5Usage();
  }

  Future<void> _load() async {
    await _vm.loadSettings();
    if (mounted) setState(() {});
  }

  /// 查询 Opus V5 体力与 Anlas；仅在官方 Token 已填时请求。
  Future<void> _loadV5Usage() async {
    final token = await sl<OfficialNovelAiTokenStore>().read();
    if (token == null || token.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _v5Usage = null;
          _v5Error = null;
          _anlas = null;
        });
      }
      return;
    }
    if (_v5Loading) return;
    _v5Loading = true;
    if (mounted) setState(() {});
    try {
      final usage =
          await sl<OfficialNovelAiApiService>().fetchV5Usage(token);
      if (mounted) {
        setState(() {
          _v5Usage = usage;
          _anlas = usage?.totalAnlas;
          _v5Error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _v5Error = error.toString().replaceFirst(
            'AppException(null): ', ''));
      }
    } finally {
      _v5Loading = false;
      if (mounted) setState(() {});
    }
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
                  onTap: () => Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                            builder: (_) => const ApiConfigPage()),
                      )
                      .then((_) => _loadV5Usage()),
                ),
              ],
            ),
            _buildV5UsageCard(),
            SizedBox(height: 18),
            _SettingsGroup(
              title: '更多功能',
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

  /// Opus V5 体力条卡片：仅在官方 Token 已填时显示。
  /// percent 为剩余百分比；isNegative 表示免费额度已扣穿。
  Widget _buildV5UsageCard() {
    final colors = Theme.of(context).colorScheme;
    // Token 未填（也没有任何加载错误）时不显示。
    if (_v5Usage == null && _v5Error == null && !_v5Loading) {
      return const SizedBox.shrink();
    }

    Widget body;
    if (_v5Loading && _v5Usage == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(child: CupertinoActivityIndicator()),
      );
    } else if (_v5Error != null) {
      body = Row(
        children: [
          Expanded(
            child: Text(
              'V5 体力查询失败：$_v5Error',
              style: TextStyle(fontSize: 12, color: colors.error),
            ),
          ),
          TextButton(
            onPressed: _loadV5Usage,
            child: const Text('重试'),
          ),
        ],
      );
    } else {
      final usage = _v5Usage!;
      final percent = usage.percent;
      final isOpus = usage.tier == 3;
      final barColor = usage.isNegative
          ? colors.error
          : percent > 50
              ? const Color(0xFF4CD97B)
              : percent > 20
                  ? const Color(0xFFF5D57A)
                  : const Color(0xFFFF8A5C);
      // 预估可画图数：1% ≈ 17 张（满条约 1,730 张，23 步 / Normal 档实测），
      // 剩余张数 ≈ percent × 17。
      const imagesPerPercent = 17;
      final estimate = usage.isNegative
          ? 0
          : (percent <= 0 ? 0 : (percent * imagesPerPercent).floor());
      final nextRefillText = _formatNextRefill(usage.nextRefill);
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  usage.isNegative ? '已用穿 · 开始扣 Anlas' : '剩余 $estimate 张',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: usage.isNegative ? colors.error : colors.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${percent.toStringAsFixed(percent == percent.roundToDouble() ? 0 : 1)}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: barColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: colors.onSurface.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              [
                if (!isOpus) '非 Opus 套餐，可能无免费 V5 额度',
                if (nextRefillText != null) '下次补充：$nextRefillText',
                '1% ≈ 17 张（23 步 · Normal）· 满条 ≈ 1,730 张',
              ].join(' · '),
              style: TextStyle(
                  fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colors.onSurface.withValues(alpha: .08),
            width: .5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(CupertinoIcons.bolt_fill,
                    size: 15, color: colors.primary),
                const SizedBox(width: 6),
                Text('Opus V5 体力',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface)),
                const Spacer(),
                if (_anlas != null) ...[
                  Icon(CupertinoIcons.circle_fill,
                      size: 8, color: const Color(0xFF7BD5F5)),
                  const SizedBox(width: 4),
                  Text('Anlas $_anlas',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF7BD5F5))),
                  const SizedBox(width: 10),
                ],
                if (!_v5Loading)
                  GestureDetector(
                    onTap: _loadV5Usage,
                    child: Icon(CupertinoIcons.refresh,
                        size: 15, color: colors.onSurfaceVariant),
                  ),
                if (_v5Loading)
                  const SizedBox.square(
                      dimension: 13,
                      child: CupertinoActivityIndicator(radius: 7)),
              ],
            ),
            const SizedBox(height: 6),
            body,
          ],
        ),
      ),
    );
  }

  String? _formatNextRefill(int? nextRefill) {
    if (nextRefill == null || nextRefill <= 0) return null;
    final dateTime =
        DateTime.fromMillisecondsSinceEpoch(nextRefill * 1000, isUtc: true)
            .toLocal();
    final now = DateTime.now();
    final diff = dateTime.difference(now);
    if (diff.inMinutes <= 0) return '即将补充';
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      return minutes > 0 ? '${hours} 小时 $minutes 分后' : '$hours 小时后';
    }
    return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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
