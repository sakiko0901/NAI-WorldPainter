import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/remote/danbooru_api_service.dart';
import 'package:nai_huishi/domain/entities/danbooru_tag.dart';
import 'package:nai_huishi/presentation/widgets/floating_toast.dart';

class DanbooruTagSearchPage extends StatefulWidget {
  const DanbooruTagSearchPage({super.key});

  @override
  State<DanbooruTagSearchPage> createState() => _DanbooruTagSearchPageState();
}

class _DanbooruTagSearchPageState extends State<DanbooruTagSearchPage> {
  late final DanbooruApiService _api;
  late final TextEditingController _controller;
  List<DanbooruTag> _results = const [];
  bool _loading = false;
  String? _error;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _api = sl<DanbooruApiService>();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
    });
    try {
      final results = await _api.search(
        query: query,
        topK: 5,
        limit: 30,
        showNsfw: true,
      );
      if (!mounted) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _error = 'Danbooru 查词失败：$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _toNovelAiTag(String tag) => tag.replaceAll('_', ' ').trim();

  Future<void> _copyTag(DanbooruTag tag) async {
    await Clipboard.setData(ClipboardData(text: _toNovelAiTag(tag.tag)));
    if (!mounted) return;
    showFloatingToast(context, '已复制 tag', icon: CupertinoIcons.doc_on_doc);
  }

  void _showTagDetails(DanbooruTag tag) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TagDetailSheet(
        tag: tag,
        novelAiTag: _toNovelAiTag(tag.tag),
        onCopy: () => _copyTag(tag),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Danbooru 查词')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(CupertinoIcons.search),
                        hintText: '输入中文或英文关键词',
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  FilledButton(
                    onPressed: _loading ? null : _search,
                    child: _loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('搜索'),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.redAccent, height: 1.5),
          ),
        ),
      );
    }
    if (_loading && _results.isEmpty) {
      return Center(child: CupertinoActivityIndicator());
    }
    if (!_searched) {
      return Center(
        child: Text(
          '输入关键词后搜索 Danbooru 标签',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          '没有找到相关 tag',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _results.length,
      itemBuilder: (context, index) => _TagCard(
        tag: _results[index],
        novelAiTag: _toNovelAiTag(_results[index].tag),
        onTap: () => _showTagDetails(_results[index]),
        onCopy: () => _copyTag(_results[index]),
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  final DanbooruTag tag;
  final String novelAiTag;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  const _TagCard({
    required this.tag,
    required this.novelAiTag,
    required this.onTap,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (tag.cnName.isNotEmpty) tag.cnName,
      if (tag.category.isNotEmpty) tag.category,
      if (tag.nsfw.isNotEmpty) tag.nsfw,
      if (tag.count > 0) '热度 ${tag.count}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          novelAiTag,
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 4),
                        SelectableText(
                          tag.tag,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '复制 NovelAI tag',
                    onPressed: onCopy,
                    icon: Icon(CupertinoIcons.doc_on_doc, size: 18),
                  ),
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                SizedBox(height: 8),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
              if (tag.wiki.trim().isNotEmpty) ...[
                SizedBox(height: 8),
                Text(
                  tag.wiki.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TagDetailSheet extends StatelessWidget {
  final DanbooruTag tag;
  final String novelAiTag;
  final VoidCallback onCopy;

  const _TagDetailSheet({
    required this.tag,
    required this.novelAiTag,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (tag.cnName.isNotEmpty) tag.cnName,
      if (tag.category.isNotEmpty) '分类：${tag.category}',
      if (tag.nsfw.isNotEmpty) 'NSFW：${tag.nsfw}',
      if (tag.count > 0) '热度：${tag.count}',
      if (tag.finalScore > 0) '得分：${tag.finalScore.toStringAsFixed(3)}',
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.82),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.16)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        novelAiTag,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onCopy,
                      icon: Icon(CupertinoIcons.doc_on_doc),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                SelectableText(
                  tag.tag,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: meta
                        .map((e) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(e, style: TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                  ),
                ],
                if (tag.wiki.trim().isNotEmpty) ...[
                  SizedBox(height: 18),
                  Text('Wiki',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  SelectableText(
                    tag.wiki.trim(),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
