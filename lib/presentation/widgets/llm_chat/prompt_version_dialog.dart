import 'package:flutter/material.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';

Future<NaiPromptVersion?> showPromptVersionDialog(BuildContext context) {
  return showDialog<NaiPromptVersion>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('选择默认画风版本'),
      content: const Text('新会话将持续使用所选版本的默认画风画师词。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(NaiPromptVersion.v45),
          child: const Text('V4.5'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(NaiPromptVersion.v5),
          child: const Text('V5'),
        ),
      ],
    ),
  );
}
