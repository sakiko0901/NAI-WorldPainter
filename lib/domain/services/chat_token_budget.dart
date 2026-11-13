import 'dart:convert';

/// Provider-independent approximation. Actual usage is shown separately when returned.
class ChatTokenBudget {
  static int text(String value) {
    var ascii = 0, other = 0;
    for (final rune in value.runes) {
      if (rune < 128) {
        ascii++;
      } else {
        other++;
      }
    }
    return (ascii / 3).ceil() + (other * 1.5).ceil();
  }

  static int content(dynamic value) {
    if (value is String) return text(value);
    if (value is List)
      return value.fold<int>(0, (n, part) => n + content(part));
    if (value is Map) {
      if (value['type'] == 'image_url') return 1600;
      if (value['type'] == 'text') return text(value['text']?.toString() ?? '');
      return text(jsonEncode(value));
    }
    return 0;
  }

  static int messages(List<Map<String, dynamic>> messages) =>
      messages
          .fold<int>(
              0,
              (n, m) =>
                  n +
                  8 +
                  content(m['content']) +
                  (m['tool_calls'] == null
                      ? 0
                      : text(jsonEncode(m['tool_calls']))));
  static int reserveOutput(int window) => (window ~/ 4).clamp(1024, 8192);
}
