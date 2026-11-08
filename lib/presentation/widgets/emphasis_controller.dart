import 'package:flutter/material.dart';

/// Editing-only colors; never rewrites the prompt or IME composing range.
class EmphasisController extends TextEditingController {
  EmphasisController({super.text}) {
    enabled.addListener(_refresh);
  }
  static final enabled = ValueNotifier<bool>(false);
  bool numericEmphasisEnabled = true;

  static bool modelSupportsNumeric(String model) =>
      RegExp(r'^nai-(?:diffusion-|v)[45](?:[-.]|$)', caseSensitive: false)
          .hasMatch(model);
  void _refresh() => notifyListeners();
  @override
  void dispose() {
    enabled.removeListener(_refresh);
    super.dispose();
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    if (!enabled.value ||
        (withComposing &&
            value.composing.isValid &&
            !value.composing.isCollapsed)) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    return TextSpan(
      style: style,
      children: emphasisSpans(text, numericEnabled: numericEmphasisEnabled),
    );
  }
}

// Match the weight transitions in NAI Launcher's NaiSyntaxController.
final _emphasisTokens = RegExp(
  r'/\*[\s\S]*?(?:\*/|$)|(?:-?(?:\d+(?:\.\d*)?|\.\d+)|-\.?|\.)?::|[{}\[\]]',
);

List<TextSpan> emphasisSpans(String text, {bool numericEnabled = true}) {
  final spans = <TextSpan>[];
  var weight = 1.0;
  var cursor = 0;

  Color? weightColor() {
    final difference = (weight - 1).abs();
    if (difference < 0.01) return null;
    final strength = (difference / (weight > 0 ? 1 : .5)).clamp(0.0, 1.0);
    final alpha = (40 * (.2 + .4 * strength)).round() / 40;
    return (weight > 1 ? const Color(0xffed5807) : const Color(0xff079ced))
        .withValues(alpha: alpha);
  }

  void add(String segment, Color? background) {
    if (segment.isEmpty) return;
    spans.add(TextSpan(
      text: segment,
      style: background == null ? null : TextStyle(backgroundColor: background),
    ));
  }

  for (final match in _emphasisTokens.allMatches(text)) {
    final token = match[0]!;
    if (token.endsWith('::') && !token.startsWith('/*') && !numericEnabled) {
      continue;
    }
    add(text.substring(cursor, match.start), weightColor());
    cursor = match.end;
    if (token.startsWith('/*')) {
      add(token, null);
    } else if (token.endsWith('::')) {
      final number = token.substring(0, token.length - 2);
      weight = number.isEmpty ? 1 : double.tryParse(number) ?? 0;
      add(token, weight == 1 ? const Color(0x807acc29) : weightColor());
    } else {
      weight = token == '{' || token == ']' ? weight * 1.05 : weight / 1.05;
      add(token, weightColor());
    }
  }
  add(text.substring(cursor), weightColor());
  return spans;
}
