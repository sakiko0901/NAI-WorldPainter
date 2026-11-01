import 'package:flutter/services.dart';
import 'package:nai_huishi/domain/entities/tag_completion.dart';

/// A replacement range excludes surrounding NovelAI weights and punctuation.
class PromptCompletionEdit {
  const PromptCompletionEdit(
      this.start, this.end, this.segmentEnd, this.query, this.existing,
      {this.artistOnly = false});
  final int start;
  final int end;
  final int segmentEnd;
  final String query;
  final Set<String> existing;
  final bool artistOnly;

  static bool _separator(String ch) => ',，\n\r'.contains(ch);

  static PromptCompletionEdit? parse(TextEditingValue value,
      {bool allowBoundary = false}) {
    if (!value.selection.isValid ||
        !value.selection.isCollapsed ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      return null;
    }
    final cursor = value.selection.extentOffset;
    if (cursor > value.text.length) return null;
    var a = cursor;
    var b = cursor;
    while (a > 0 && !_separator(value.text[a - 1])) {
      a--;
    }
    while (b < value.text.length && !_separator(value.text[b])) {
      b++;
    }
    final range = _contentRange(value.text.substring(a, b));
    final start = a + range.$1;
    final end = a + range.$2;
    if (start >= end || (!allowBoundary && (cursor < start || cursor > end))) {
      return null;
    }
    final query = normalizeCompletionTag(value.text.substring(start, end));
    // Free-form paragraphs and incomplete weight expressions are not tags.
    if (query.length > 100 || query.contains('::') || query.contains('<|')) {
      return null;
    }
    final existing = <String>{};
    var offset = 0;
    for (final segment in value.text.split(RegExp('[,，\n\r]'))) {
      if (offset != a) {
        final r = _contentRange(segment);
        final tag = normalizeCompletionTag(segment.substring(r.$1, r.$2));
        if (tag.isNotEmpty) existing.add(tag);
      }
      offset += segment.length + 1;
    }
    return PromptCompletionEdit(start, end, b, query, existing,
        artistOnly:
            value.text.substring(a, start).toLowerCase().contains('artist:'));
  }

  static (int, int) _contentRange(String text) {
    var start = 0;
    var end = text.length;
    final prefix =
        RegExp(r'^\s*(?:(?:\{|\[|[+-]?\d+(?:\.\d+)?::)\s*)*').firstMatch(text)!;
    start = prefix.end;
    final suffix = RegExp(r'(?:\s|\}|\]|::)*$').firstMatch(text)!;
    end = suffix.start;
    if (end < start) return (start, start);
    final middle = text.substring(start, end);
    // Parentheses in canonical names and kaomoji are literal, except (tag:1.2).
    if (middle.startsWith('(') &&
        RegExp(r':\s*[+-]?\d+(?:\.\d+)?\)$').hasMatch(middle)) {
      start++;
      end = start -
          1 +
          RegExp(r':\s*[+-]?\d+(?:\.\d+)?\)$').firstMatch(middle)!.start;
    }
    if (text.substring(start, end).toLowerCase().startsWith('artist:')) {
      start += 7;
    }
    while (start < end && text[start].trim().isEmpty) {
      start++;
    }
    while (end > start && text[end - 1].trim().isEmpty) {
      end--;
    }
    return (start, end);
  }

  TextEditingValue apply(TextEditingValue value, String canonicalTag,
      {bool autoComma = true, bool related = false}) {
    final tag = canonicalTag.replaceAll('_', ' ');
    if (related) {
      final before = value.text.substring(0, segmentEnd).trimRight();
      final after = value.text.substring(segmentEnd);
      final insert = ', $tag';
      final tail = after.isEmpty && autoComma ? ', ' : '';
      return TextEditingValue(
          text: '$before$insert$tail$after',
          selection: TextSelection.collapsed(
              offset: before.length + insert.length + tail.length));
    }
    var text = value.text.replaceRange(start, end, tag);
    var cursor = segmentEnd + tag.length - (end - start);
    if (autoComma) {
      if (cursor == text.length) {
        text = '${text.trimRight()}, ';
        cursor = text.length;
      } else if (text[cursor] == ',' || text[cursor] == '，') {
        cursor++;
        while (cursor < text.length && text[cursor] == ' ') {
          cursor++;
        }
        if (cursor == text.length || text[cursor - 1] != ' ') {
          text = text.replaceRange(cursor, cursor, ' ');
          cursor++;
        }
      }
    } else {
      cursor = start + tag.length;
    }
    return TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: cursor));
  }
}
