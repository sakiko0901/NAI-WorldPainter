import 'package:flutter/foundation.dart';
import 'package:nai_huishi/domain/entities/llm_session.dart';
import 'package:nai_huishi/domain/entities/llm_session_search_result.dart';
import 'package:nai_huishi/domain/entities/nai_prompt_version.dart';
import 'package:nai_huishi/presentation/viewmodels/llm_chat_viewmodel.dart';

/// Panel-only fake: no global injection or shared chat fixture mutations.
class SessionHistoryFake extends ChangeNotifier implements LlmChatViewModel {
  SessionHistoryFake(this.data);

  List<LlmSession> data;
  final searchQueries = <String>[];
  final actions = <String>[];
  final failures = <String>{};
  Future<List<LlmSessionSearchResult>> Function(String)? onSearch;
  Future<void> Function()? onPin;

  @override
  String? activeSessionId;
  @override
  String? errorMessage;
  @override
  bool isSending = false;

  @override
  List<LlmSession> get sessions => List.unmodifiable(data);

  void replaceSessions(List<LlmSession> sessions) {
    data = sessions;
    notifyListeners();
  }

  @override
  void clearError() {
    errorMessage = null;
    notifyListeners();
  }

  void _record(String action) {
    actions.add(action);
    if (failures.contains(action)) throw StateError('Test failure: $action');
  }

  @override
  Future<List<LlmSessionSearchResult>> searchSessions(String query) async {
    searchQueries.add(query);
    if (onSearch != null) return onSearch!(query);
    return [
      for (final s in data)
        if (s.title.toLowerCase().contains(query.toLowerCase()))
          LlmSessionSearchResult(session: s),
    ];
  }

  @override
  Future<void> setSessionPinned(String id, bool pinned) async {
    _record('pin:$id:$pinned');
    await onPin?.call();
    replaceSessions([
      for (final s in data)
        if (s.id == id)
          s.copyWith(
              pinnedAt: pinned ? DateTime.now() : null, clearPinnedAt: !pinned)
        else
          s,
    ]);
  }

  @override
  Future<void> renameSession(String id, String title) async {
    _record('rename:$id:$title');
    replaceSessions([
      for (final s in data) s.id == id ? s.copyWith(title: title) : s,
    ]);
  }

  @override
  Future<void> deleteSession(String id) async {
    _record('delete:$id');
    replaceSessions(data.where((s) => s.id != id).toList());
  }

  @override
  Future<void> deleteAllSessions() async {
    _record('clear');
    replaceSessions([]);
  }

  @override
  Future<void> selectSession(String id) async {
    _record('select:$id');
    activeSessionId = id;
    notifyListeners();
  }

  @override
  Future<void> createNewSession({
    NaiPromptVersion promptVersion = NaiPromptVersion.v5,
  }) async {
    _record('create');
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

LlmSession historySession(
  String id, {
  String? title,
  DateTime? updatedAt,
  DateTime? pinnedAt,
}) =>
    LlmSession(
      id: id,
      title: title ?? '会话 $id',
      createdAt:
          updatedAt ?? DateTime.now().subtract(const Duration(minutes: 1)),
      updatedAt:
          updatedAt ?? DateTime.now().subtract(const Duration(minutes: 1)),
      pinnedAt: pinnedAt,
    );
