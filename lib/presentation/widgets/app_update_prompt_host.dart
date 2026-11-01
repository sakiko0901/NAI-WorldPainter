import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nai_huishi/core/services/app_update_install_guard.dart';
import 'package:nai_huishi/core/services/app_update_service.dart';
import 'package:nai_huishi/domain/entities/app_update.dart';
import 'package:nai_huishi/presentation/pages/app_update_page.dart';

/// Presents automatic check results only when the home route is safe to interrupt.
class AppUpdatePromptHost extends StatefulWidget {
  final AppUpdateService service;
  final AppUpdateInstallGuard guard;
  final GlobalKey<NavigatorState> navigatorKey;
  final ValueListenable<bool> rootRouteCurrent;
  final Widget child;

  const AppUpdatePromptHost({
    super.key,
    required this.service,
    required this.guard,
    required this.navigatorKey,
    required this.rootRouteCurrent,
    required this.child,
  });

  @override
  State<AppUpdatePromptHost> createState() => _AppUpdatePromptHostState();
}

class _AppUpdatePromptHostState extends State<AppUpdatePromptHost>
    with WidgetsBindingObserver {
  final _shownVersions = <int>{};
  Timer? _retry;
  bool _scheduled = false;
  bool _presenting = false;
  late bool _foreground;
  late int _seenCheckRevision;
  bool _startupFeedbackHandled = false;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _seenCheckRevision = widget.service.lastCheckResult?.revision ?? 0;
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_requestEvaluation);
    _listen(widget);
    _requestEvaluation();
  }

  void _listen(AppUpdatePromptHost host) {
    host.service.addListener(_onServiceChanged);
    host.guard.addListener(_requestEvaluation);
    host.rootRouteCurrent.addListener(_requestEvaluation);
  }

  void _unlisten(AppUpdatePromptHost host) {
    host.service.removeListener(_onServiceChanged);
    host.guard.removeListener(_requestEvaluation);
    host.rootRouteCurrent.removeListener(_requestEvaluation);
  }

  @override
  void didUpdateWidget(covariant AppUpdatePromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.guard != widget.guard ||
        oldWidget.rootRouteCurrent != widget.rootRouteCurrent) {
      _unlisten(oldWidget);
      _listen(widget);
      if (oldWidget.service != widget.service) {
        _seenCheckRevision = widget.service.lastCheckResult?.revision ?? 0;
        _startupFeedbackHandled = false;
      }
    }
    _requestEvaluation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // View insets can change without a service or navigation notification.
    MediaQuery.viewInsetsOf(context);
    _requestEvaluation();
  }

  @override
  void didChangeMetrics() => _requestEvaluation();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _requestEvaluation();
  }

  AppUpdateManifest? get _candidate {
    final service = widget.service;
    final candidate = service.automaticPromptManifest;
    final installed = service.installed;
    if (candidate == null ||
        service.automaticPromptRevision <= 0 ||
        installed == null ||
        !service.autoCheckEnabled ||
        !service.hasUpdate ||
        service.phase != UpdatePhase.available ||
        candidate.versionCode <= installed.versionCode ||
        candidate.versionCode != service.manifest?.versionCode ||
        _shownVersions.contains(candidate.versionCode)) {
      return null;
    }
    return candidate;
  }

  void _onServiceChanged() {
    _requestEvaluation();
    final result = widget.service.lastCheckResult;
    if (result == null || result.revision <= _seenCheckRevision) return;
    _seenCheckRevision = result.revision;
    if (_startupFeedbackHandled ||
        result.origin != AppUpdateCheckOrigin.startup) {
      return;
    }
    // A routine success notice has no backlog: a busy/backgrounded startup
    // consumes it as well. New-version dialogs keep their existing deferral.
    _startupFeedbackHandled = true;
    if (!_foreground ||
        !result.notifyUser ||
        (result.outcome != AppUpdateCheckOutcome.upToDate &&
            result.outcome != AppUpdateCheckOutcome.ahead)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_foreground || _presenting) return;
      final service = widget.service;
      final installed = service.installed;
      final manifest = result.manifest;
      final navigator = widget.navigatorKey.currentState;
      if (service.lastCheckResult?.revision != result.revision ||
          service.lastCheckResult?.notifyUser != true ||
          service.isLastCheckResultStale ||
          !service.autoCheckEnabled ||
          service.isChecking ||
          service.phase != UpdatePhase.upToDate ||
          installed == null ||
          manifest == null ||
          manifest.versionCode != service.manifest?.versionCode ||
          manifest.versionCode > installed.versionCode ||
          (result.outcome == AppUpdateCheckOutcome.upToDate &&
              manifest.versionCode != installed.versionCode) ||
          (result.outcome == AppUpdateCheckOutcome.ahead &&
              manifest.versionCode >= installed.versionCode) ||
          !_canPresentAtHome(navigator) ||
          _hasSnackBar(navigator!.context)) {
        return;
      }
      ScaffoldMessenger.maybeOf(navigator.overlay!.context)?.showSnackBar(
        SnackBar(
          key: const ValueKey('automatic-update-current'),
          duration: const Duration(seconds: 3),
          content: Text(result.outcome == AppUpdateCheckOutcome.ahead
              ? '当前版本较新，无需更新'
              : '已是最新版本'),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // ScaffoldMessenger queues messages but has no public queue getter. Inspect
  // the mounted navigator subtree once per startup result, never during build
  // or on progress ticks. Existing feedback takes priority over this notice.
  bool _hasSnackBar(BuildContext subtree) {
    var found = false;
    void visit(Element element) {
      if (found) return;
      if (element.widget is SnackBar) {
        found = true;
        return;
      }
      element.visitChildElements(visit);
    }

    subtree.visitChildElements(visit);
    return found;
  }

  bool _canPresentAtHome(NavigatorState? navigator) {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    final editing =
        focusContext?.findAncestorStateOfType<EditableTextState>() != null;
    return navigator != null &&
        navigator.mounted &&
        navigator.overlay != null &&
        !navigator.canPop() &&
        widget.rootRouteCurrent.value &&
        !widget.service.isBusy &&
        widget.guard.blockReason == null &&
        widget.guard.unsavedWarning == null &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        !editing;
  }

  void _requestEvaluation() {
    _retry?.cancel();
    _retry = null;
    if (!mounted || !_foreground || _presenting || _candidate == null) return;
    if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _evaluate();
      });
    }
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _evaluate() {
    final candidate = _candidate;
    if (!_foreground || _presenting || candidate == null) return;
    final navigator = widget.navigatorKey.currentState;
    if (!_canPresentAtHome(navigator)) {
      // Callback-based workspace guards do not all emit changes. Retry only
      // while a candidate is pending and the app is foregrounded.
      _retry = Timer(const Duration(seconds: 5), _requestEvaluation);
      return;
    }
    unawaited(_present(candidate, navigator!));
  }

  Future<void> _present(
      AppUpdateManifest candidate, NavigatorState navigator) async {
    _presenting = true;
    try {
      final result = showDialog<_UpdatePromptChoice>(
        context: navigator.overlay!.context,
        builder: (context) => _AutomaticUpdateDialog(manifest: candidate),
      );
      // The route was pushed successfully. Deferrals never consume the event.
      _shownVersions.add(candidate.versionCode);
      widget.service.acknowledgeAutomaticPrompt(candidate.versionCode);
      final choice = await result;
      if (!mounted) return;
      if (choice == _UpdatePromptChoice.ignore) {
        // The candidate might have changed while the dialog was open.
        if (widget.service.manifest?.versionCode == candidate.versionCode) {
          await widget.service.ignoreVersion();
        }
      } else if (choice == _UpdatePromptChoice.view && navigator.mounted) {
        await navigator.push<void>(CupertinoPageRoute(
          builder: (_) => AppUpdatePage(service: widget.service),
        ));
      }
    } catch (_) {
      // An automatic prompt must not surface platform or navigation details.
    } finally {
      _presenting = false;
      if (mounted) _requestEvaluation();
    }
  }

  @override
  void dispose() {
    _retry?.cancel();
    _unlisten(widget);
    FocusManager.instance.removeListener(_requestEvaluation);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _UpdatePromptChoice { later, ignore, view }

class _AutomaticUpdateDialog extends StatelessWidget {
  final AppUpdateManifest manifest;

  const _AutomaticUpdateDialog({required this.manifest});

  @override
  Widget build(BuildContext context) {
    const previewLimit = 1200;
    final notes = manifest.releaseNotes.trim();
    final preview = String.fromCharCodes(notes.runes.take(previewLimit));
    final truncated = preview.length < notes.length;
    return AlertDialog(
      key: const ValueKey('automatic-update-dialog'),
      scrollable: true,
      title: const Text('发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${manifest.versionName}（${manifest.versionCode}）',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            notes.isEmpty ? '此版本未提供更新说明。' : preview,
            key: const ValueKey('automatic-update-notes'),
          ),
          if (truncated) ...[
            const SizedBox(height: 12),
            const Text('更多更新说明可在软件更新中查看。'),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('automatic-update-later'),
          onPressed: () => Navigator.of(context).pop(_UpdatePromptChoice.later),
          child: const Text('稍后'),
        ),
        TextButton(
          key: const ValueKey('automatic-update-ignore'),
          onPressed: () =>
              Navigator.of(context).pop(_UpdatePromptChoice.ignore),
          child: const Text('忽略此版本'),
        ),
        FilledButton(
          key: const ValueKey('automatic-update-view'),
          onPressed: () => Navigator.of(context).pop(_UpdatePromptChoice.view),
          child: const Text('查看更新'),
        ),
      ],
    );
  }
}
