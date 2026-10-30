import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nai_huishi/data/datasources/local/reference_image_importer.dart';

class ReferenceMetadataDialog extends StatefulWidget {
  final PreparedReferenceImage image;
  const ReferenceMetadataDialog({super.key, required this.image});

  @override
  State<ReferenceMetadataDialog> createState() =>
      _ReferenceMetadataDialogState();
}

class _ReferenceMetadataDialogState extends State<ReferenceMetadataDialog> {
  late final Map<String, (String, String)> fields;
  final Set<String> selected = {};

  @override
  void initState() {
    super.initState();
    final tags = widget.image.metadata;
    final metadata = tags?.metadata ?? {};
    fields = {
      if (tags != null && tags.selectedGeneralTags.isNotEmpty)
        'prompt': ('正向提示词', tags.selectedGeneralTags),
      if (tags?.negativePrompt != null)
        'negative': ('负向提示词', tags!.negativePrompt!),
      if (tags?.characters?.isNotEmpty ?? false)
        'characters': ('角色提示词', '${tags!.characters!.length} 个角色'),
      if (metadata['width'] != null && metadata['height'] != null)
        'size': ('图像尺寸', '${metadata['width']} × ${metadata['height']}'),
      for (final entry in const {
        'seed': 'Seed',
        'steps': '步数',
        'scale': '引导比例',
        'cfg_rescale': '提示词引导重缩放',
        'sampler': '采样算法',
        'noise_schedule': '噪声调度',
      }.entries)
        if (metadata[entry.key] != null)
          entry.key: (entry.value, '${metadata[entry.key]}'),
    };
    selected.addAll(fields.keys);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(fields.isEmpty ? '未发现原图参数' : '选择导入的数据'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(File(widget.image.path),
                      height: 160, fit: BoxFit.contain, cacheWidth: 480)),
              const SizedBox(height: 12),
              Text(
                  fields.isEmpty
                      ? '图片已压缩。可以继续裁剪，当前生成参数保持不变。'
                      : '图片已压缩。仅将勾选的数据应用到生成参数，然后进入裁剪。',
                  style: Theme.of(context).textTheme.bodySmall),
              for (final entry in fields.entries)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value.$1),
                  subtitle: Text(entry.value.$2,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  value: selected.contains(entry.key),
                  onChanged: (value) => setState(() {
                    value == true
                        ? selected.add(entry.key)
                        : selected.remove(entry.key);
                  }),
                ),
            ],
          )),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('继续')),
        ],
      );
}
