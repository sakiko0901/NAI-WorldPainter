import 'package:nai_huishi/domain/entities/llm_session_search_result.dart';

// Calendar days preserve midnight boundaries across daylight-saving changes.
int _dayNumber(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

class ChatSessionTimelineGroup {
  final String label;
  final List<LlmSessionSearchResult> entries;
  const ChatSessionTimelineGroup(this.label, this.entries);
}

List<ChatSessionTimelineGroup> groupChatSessionTimeline(
  Iterable<LlmSessionSearchResult> entries, {
  required DateTime now,
}) {
  final localNow = now.toLocal();
  final today = _dayNumber(localNow);
  final sorted = entries.toList()
    ..sort((a, b) {
      final pinned =
          (b.session.isPinned ? 1 : 0) - (a.session.isPinned ? 1 : 0);
      if (pinned != 0) return pinned;
      final updated = b.session.updatedAt.compareTo(a.session.updatedAt);
      return updated != 0 ? updated : a.session.id.compareTo(b.session.id);
    });
  final groups = <String, List<LlmSessionSearchResult>>{};
  for (final entry in sorted) {
    final session = entry.session;
    final local = session.updatedAt.toLocal();
    final age = today - _dayNumber(local);
    final String label;
    if (session.isPinned) {
      label = '置顶';
    } else if (local.isAfter(localNow)) {
      label = '未来日期';
    } else if (age == 0) {
      label = '今天';
    } else if (age == 1) {
      label = '昨天';
    } else if (age < 7) {
      // Today and the six preceding calendar days.
      label = '近7天';
    } else {
      label = '${local.year}年${local.month}月';
    }
    (groups[label] ??= []).add(entry);
  }
  return [
    for (final group in groups.entries)
      ChatSessionTimelineGroup(group.key, List.unmodifiable(group.value)),
  ];
}

String formatChatSessionTime(DateTime date, {required DateTime now}) {
  final local = date.toLocal();
  final localNow = now.toLocal();
  final age = _dayNumber(localNow) - _dayNumber(local);
  String two(int value) => value.toString().padLeft(2, '0');
  if (!local.isAfter(localNow)) {
    if (age == 0) return '${two(local.hour)}:${two(local.minute)}';
    if (age > 0 && age < 7) {
      return '星期${const [
        '一',
        '二',
        '三',
        '四',
        '五',
        '六',
        '日'
      ][local.weekday - 1]}';
    }
  }
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}
