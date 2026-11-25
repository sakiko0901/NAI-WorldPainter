import 'package:flutter/cupertino.dart';
import 'package:nai_huishi/core/di/injection.dart';
import 'package:nai_huishi/data/datasources/local/catalog_reference_workspace_file.dart';
import 'package:nai_huishi/data/repositories/character_reference_catalog_repository.dart';
import 'package:nai_huishi/domain/entities/generation_task.dart';
import 'package:nai_huishi/presentation/navigation/studio_page_route.dart';
import 'package:nai_huishi/presentation/pages/character_reference_library_page.dart';
import 'package:nai_huishi/presentation/viewmodels/generation_viewmodel.dart';
import 'package:nai_huishi/presentation/widgets/studio_alert_dialog.dart';

Future<bool> openCharacterReferenceLibrary(
  BuildContext context,
  GenerationViewModel workspace,
) async {
  final applied = await Navigator.of(context, rootNavigator: true)
      .push(studioPageRoute<bool>(
    context: context,
    name: '/character-reference-library',
    builder: (libraryContext) => ListenableBuilder(
      listenable: workspace,
      builder: (_, __) {
        final supportsPrecise = !workspace.isNonNovelAiProvider &&
            workspace.supportsPreciseReferences;
        final supportsVibe =
            !workspace.isNonNovelAiProvider && workspace.supportsVibeReferences;
        return CharacterReferenceLibraryPage(
          repository: sl<CharacterReferenceCatalogRepository>(),
          onApplyPrecise: supportsPrecise
              ? (reference) => _applyReference(libraryContext, workspace,
                  ReferenceMode.precise, reference.path)
              : null,
          onApplyVibe: supportsVibe
              ? (reference) => _applyReference(
                  libraryContext, workspace, ReferenceMode.vibe, reference.path)
              : null,
          applyUnavailableReason: supportsPrecise || supportsVibe
              ? null
              : '当前模型或渠道不支持角色精确参考和氛围转移。仍可保存参考图。',
        );
      },
    ),
  ));
  return applied == true;
}

Future<bool> confirmReferenceModeSwitch(
  BuildContext context,
  GenerationViewModel workspace,
  ReferenceMode target,
) async {
  final current = workspace.referenceMode;
  if (current == target) return true;
  final hasCurrentReferences = current == ReferenceMode.vibe
      ? workspace.vibeReferences.isNotEmpty
      : workspace.preciseReferences.isNotEmpty;
  if (!hasCurrentReferences) return true;

  final targetLabel = target == ReferenceMode.vibe ? '氛围转移' : '角色精确参考';
  final currentLabel = current == ReferenceMode.vibe ? '氛围参考图' : '角色精确参考图';
  final confirmed = await showStudioAlertDialog<bool>(
    context: context,
    builder: (dialogContext) => StudioAlertDialog(
      title: Text('切换为$targetLabel？'),
      content: Text('切换后会清空当前的$currentLabel。'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('清空并切换'),
        ),
      ],
    ),
  );
  return confirmed == true && context.mounted;
}

Future<bool> _applyReference(
  BuildContext context,
  GenerationViewModel workspace,
  ReferenceMode mode,
  String sourcePath,
) async {
  _checkWorkspaceAvailability(workspace, mode);
  if (!await confirmReferenceModeSwitch(context, workspace, mode) ||
      !context.mounted) {
    return false;
  }

  final path = await copyCatalogReferenceToWorkspace(sourcePath);
  if (!context.mounted) return false;
  _checkWorkspaceAvailability(workspace, mode);

  if (mode == ReferenceMode.precise) {
    final references = workspace.preciseReferences;
    if (references.any((reference) => reference.path == path)) {
      throw StateError('工作台已添加这张角色精确参考图。');
    }
    await workspace.addPreciseReference(path, referenceType: 'character');
  } else {
    final references = workspace.vibeReferences;
    if (references.any((reference) => reference.path == path)) {
      throw StateError('工作台已添加这张氛围参考图。');
    }
    return await workspace.addVibeReferences([path]) > 0;
  }
  return true;
}

void _checkWorkspaceAvailability(
    GenerationViewModel workspace, ReferenceMode mode) {
  if (workspace.isGenerating || workspace.isProcessingImage) {
    throw StateError('工作台正在处理图片，请完成后再添加参考图。');
  }
  final supported = mode == ReferenceMode.precise
      ? workspace.supportsPreciseReferences
      : workspace.supportsVibeReferences;
  if (workspace.isNonNovelAiProvider || !supported) {
    throw StateError('当前模型或渠道不支持此参考方式。');
  }
  if (mode == ReferenceMode.precise &&
      workspace.preciseReferences.length >= 4) {
    throw StateError('工作台最多支持 4 张角色精确参考图。');
  }
  if (mode == ReferenceMode.vibe &&
      workspace.vibeReferences.length >= workspace.maxVibeReferences) {
    throw StateError('当前渠道最多支持 ${workspace.maxVibeReferences} 张氛围参考图。');
  }
}
