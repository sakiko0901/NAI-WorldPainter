import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_session_search_result.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_session_timeline.dart';

import '../../support/session_history_fake.dart';

void main() {
  final now = DateTime(2026, 11, 14, 12);
  LlmSessionSearchResult entry(String id, DateTime date,
          {bool pinned = false}) =>
      LlmSessionSearchResult(
          session: historySession(id,
              updatedAt: date, pinnedAt: pinned ? now : null));

  test('pinned first, local calendar groups, updated descending in every group',
      () {
    final input = [
      entry('old-pin', DateTime(2025, 12, 1), pinned: true),
      entry('old', DateTime(2026, 10, 30)),
      entry('today-old', DateTime(2026, 11, 14, 1)),
      entry('month', DateTime(2026, 11, 7, 23, 59)),
      entry('recent-old', DateTime(2026, 11, 8)),
      entry('yesterday', DateTime(2026, 11, 13, 23, 59)),
      entry('today-new', DateTime(2026, 11, 14, 11)),
      entry('new-pin', DateTime(2026, 11, 14, 10), pinned: true),
      entry('recent-new', DateTime(2026, 11, 12)),
    ];
    final before = List.of(input);
    final groups = groupChatSessionTimeline(input, now: now);
    expect(groups.map((g) => g.label),
        ['置顶', '今天', '昨天', '近7天', '2026年11月', '2026年10月']);
    expect(
        groups.first.entries.map((r) => r.session.id), ['new-pin', 'old-pin']);
    expect(
        groups[1].entries.map((r) => r.session.id), ['today-new', 'today-old']);
    expect(groups[3].entries.map((r) => r.session.id),
        ['recent-new', 'recent-old']);
    expect(input, before);
  });

  test('future dates including later today never leak into today or recent',
      () {
    final groups = groupChatSessionTimeline([
      entry('tomorrow', DateTime(2026, 11, 15)),
      entry('later-today', now.add(const Duration(seconds: 1))),
      entry('present', now),
    ], now: now);
    expect(groups.map((g) => g.label), ['未来日期', '今天']);
    expect(groups.first.entries.map((r) => r.session.id),
        ['tomorrow', 'later-today']);
    expect(formatChatSessionTime(now.add(const Duration(seconds: 1)), now: now),
        '2026/11/14');
  });

  test('UTC instants use the user local midnight, not UTC date', () {
    final localNow = DateTime(2026, 1, 1, 0, 5);
    final groups = groupChatSessionTimeline([
      entry('now', localNow.toUtc()),
      entry('before-midnight', DateTime(2025, 12, 31, 23, 59).toUtc()),
      entry('last-week', DateTime(2025, 12, 25, 23, 59).toUtc()),
    ], now: localNow.toUtc());
    expect(groups.map((g) => g.label), ['今天', '昨天', '2025年12月']);
    expect(formatChatSessionTime(localNow.toUtc(), now: localNow), '00:05');
  });

  test('time labels use HH:mm, weekday within seven calendar days, then date',
      () {
    expect(
        formatChatSessionTime(DateTime(2026, 11, 14, 9, 4), now: now), '09:04');
    expect(formatChatSessionTime(DateTime(2026, 11, 13), now: now), '星期五');
    expect(formatChatSessionTime(DateTime(2026, 11, 8), now: now), '星期日');
    expect(formatChatSessionTime(DateTime(2026, 11, 7, 23, 59), now: now),
        '2026/11/07');
    expect(formatChatSessionTime(DateTime(2027), now: now), '2027/01/01');
  });

  test('local calendar boundaries also hold on DST transition dates', () {
    for (final day in [DateTime(2026, 3, 9), DateTime(2026, 11, 2)]) {
      final before = DateTime(day.year, day.month, day.day - 1, 0, 1);
      final groups =
          groupChatSessionTimeline([entry('previous-day', before)], now: day);
      expect(groups.single.label, '昨天');
    }
  });
}
