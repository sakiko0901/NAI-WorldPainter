import 'package:flutter/material.dart';
import 'package:nai_huishi/presentation/app_theme.dart';

/// Zero-dependency, lightweight Markdown renderer tailored for AI prompt
/// assistant replies: renders headings, bold/italic, inline code pills
/// (e.g. Danbooru tags), fenced code blocks, blockquotes, and true hanging-
/// indent bullet/ordered lists without breaking underscores in Danbooru tags.
class ChatMarkdownText extends StatelessWidget {
  final String text;
  final TextStyle baseStyle;
  final bool editorialSerif;

  const ChatMarkdownText({
    super.key,
    required this.text,
    required this.baseStyle,
    this.editorialSerif = false,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final glass = FrostedTheme.of(context);
    final isCoffeePaper = glass.appearanceMode == AppearanceMode.coffeePaper;
    final proseStyle = editorialSerif
        ? baseStyle.copyWith(
            fontFamily: 'sans-serif',
            fontFamilyFallback: zhFallback,
          )
        : baseStyle;

    final blocks = _parseBlocks(trimmed);
    if (blocks.length == 1 && blocks.first is _ParagraphBlock) {
      return _buildRichSelectable(
        context,
        (blocks.first as _ParagraphBlock).text,
        proseStyle,
        theme,
        glass,
        isCoffeePaper,
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (i > 0) {
        final prev = blocks[i - 1];
        final compact = prev is _ListItemBlock && block is _ListItemBlock;
        final headingGap = block is _HeadingBlock;
        children.add(SizedBox(
          height: headingGap ? 14 : (compact ? 6 : 10),
        ));
      }
      children.add(switch (block) {
        _HeadingBlock(:final level, :final text) => _buildRichSelectable(
            context,
            text,
            proseStyle.copyWith(
              fontSize: (proseStyle.fontSize ?? 15) +
                  switch (level) { 1 => 3.5, 2 => 2.0, _ => 0.5 },
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            theme,
            glass,
            isCoffeePaper,
          ),
        _ParagraphBlock(:final text) => _buildRichSelectable(
            context,
            text,
            proseStyle,
            theme,
            glass,
            isCoffeePaper,
          ),
        _ListItemBlock(:final marker, :final text, :final indent) => Padding(
            padding: EdgeInsetsDirectional.only(start: indent * 14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: marker == '•' ? 18 : 24,
                  child: Text(
                    marker,
                    style: proseStyle.copyWith(
                      fontWeight:
                          marker == '•' ? FontWeight.w700 : FontWeight.w500,
                      color: marker == '•'
                          ? proseStyle.color
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildRichSelectable(
                    context,
                    text,
                    proseStyle,
                    theme,
                    glass,
                    isCoffeePaper,
                  ),
                ),
              ],
            ),
          ),
        _CodeBlock(:final code, :final language) => Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
            decoration: BoxDecoration(
              color: isCoffeePaper
                  ? theme.colorScheme.surfaceContainerHigh
                  : theme.colorScheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCoffeePaper
                    ? glass.border
                    : theme.colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (language.isNotEmpty) ...[
                  Text(
                    language,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                SelectableText(
                  code,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        _BlockquoteBlock(:final text) => Container(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  width: 2.5,
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: _buildRichSelectable(
              context,
              text,
              proseStyle.copyWith(color: theme.colorScheme.onSurfaceVariant),
              theme,
              glass,
              isCoffeePaper,
            ),
          ),
        _DividerBlock() => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Divider(height: 1, color: glass.border),
          ),
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _buildRichSelectable(
    BuildContext context,
    String source,
    TextStyle style,
    ThemeData theme,
    FrostedTheme glass,
    bool isCoffeePaper,
  ) {
    final spans = _parseInline(
      source,
      baseStyle: style,
      theme: theme,
      glass: glass,
      isCoffeePaper: isCoffeePaper,
      mixedLatinSerif: editorialSerif,
    );
    return SelectableText.rich(
      TextSpan(style: style, children: spans),
      contextMenuBuilder: (context, editableTextState) {
        return AdaptiveTextSelectionToolbar.editableText(
          editableTextState: editableTextState,
        );
      },
    );
  }
}

sealed class _MarkdownBlock {
  const _MarkdownBlock();
}

class _HeadingBlock extends _MarkdownBlock {
  final int level;
  final String text;
  const _HeadingBlock(this.level, this.text);
}

class _ParagraphBlock extends _MarkdownBlock {
  final String text;
  const _ParagraphBlock(this.text);
}

class _ListItemBlock extends _MarkdownBlock {
  final String marker;
  final String text;
  final int indent;
  const _ListItemBlock(this.marker, this.text, {this.indent = 0});
}

class _CodeBlock extends _MarkdownBlock {
  final String language;
  final String code;
  const _CodeBlock(this.language, this.code);
}

class _BlockquoteBlock extends _MarkdownBlock {
  final String text;
  const _BlockquoteBlock(this.text);
}

class _DividerBlock extends _MarkdownBlock {
  const _DividerBlock();
}

final _headingRe = RegExp(r'^(#{1,4})\s+(.+)$');
final _bulletRe = RegExp(r'^(\s*)[-*•]\s+(.+)$');
final _orderedRe = RegExp(r'^(\s*)(\d+\.)\s+(.+)$');
final _dividerRe = RegExp(r'^([-*_])\1{2,}\s*$');
final _quoteRe = RegExp(r'^>\s?(.*)$');

List<_MarkdownBlock> _parseBlocks(String input) {
  final lines = input.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_MarkdownBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(_ParagraphBlock(paragraph.join('\n')));
    paragraph.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final raw = lines[i];
    final trimmed = raw.trim();

    if (trimmed.startsWith('```')) {
      flushParagraph();
      final lang = trimmed.substring(3).trim();
      final codeLines = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        codeLines.add(lines[i]);
        i++;
      }
      if (i < lines.length) i++;
      blocks.add(_CodeBlock(lang, codeLines.join('\n').trimRight()));
      continue;
    }

    if (trimmed.isEmpty) {
      flushParagraph();
      i++;
      continue;
    }

    if (_dividerRe.hasMatch(trimmed)) {
      flushParagraph();
      blocks.add(const _DividerBlock());
      i++;
      continue;
    }

    final heading = _headingRe.firstMatch(trimmed);
    if (heading != null) {
      flushParagraph();
      blocks.add(_HeadingBlock(heading.group(1)!.length, heading.group(2)!));
      i++;
      continue;
    }

    final bullet = _bulletRe.firstMatch(raw);
    if (bullet != null) {
      flushParagraph();
      final indent = (bullet.group(1)!.length ~/ 2).clamp(0, 3);
      blocks.add(_ListItemBlock('•', bullet.group(2)!, indent: indent));
      i++;
      continue;
    }

    final ordered = _orderedRe.firstMatch(raw);
    if (ordered != null) {
      flushParagraph();
      final indent = (ordered.group(1)!.length ~/ 2).clamp(0, 3);
      blocks.add(
        _ListItemBlock(ordered.group(2)!, ordered.group(3)!, indent: indent),
      );
      i++;
      continue;
    }

    final quote = _quoteRe.firstMatch(trimmed);
    if (quote != null) {
      flushParagraph();
      final quoteLines = <String>[quote.group(1)!];
      i++;
      while (i < lines.length) {
        final next = _quoteRe.firstMatch(lines[i].trim());
        if (next == null) break;
        quoteLines.add(next.group(1)!);
        i++;
      }
      blocks.add(_BlockquoteBlock(quoteLines.join('\n').trim()));
      continue;
    }

    paragraph.add(raw);
    i++;
  }

  flushParagraph();
  return blocks;
}

// Intentionally avoids single-underscore italic so Danbooru tags like
// `evanescia_(honkai:_star_rail)` never get mangled.
final _inlineTokenRe = RegExp(
  r'`([^`\n]+)`'
  r'|\*\*\*([^\*\n]+?)\*\*\*'
  r'|\*\*([^\*\n]+?)\*\*'
  r'|~~([^~\n]+?)~~'
  r'|\[([^\]\n]+)\]\(([^)\s]+)\)'
  r'|\*([^\s\*][^\*\n]*?[^\s\*]|[^\s\*])\*',
);

final _latinSerifRe = RegExp(r'[A-Za-z0-9]+(?:[._\-/+:][A-Za-z0-9]+)*');

List<InlineSpan> _styledTextSpans(
  String text, {
  TextStyle? extraStyle,
  required bool mixedLatinSerif,
}) {
  if (!mixedLatinSerif || text.isEmpty) {
    return [TextSpan(text: text, style: extraStyle)];
  }
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in _latinSerifRe.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(
        text: text.substring(cursor, match.start),
        style: extraStyle,
      ));
    }
    final latinStyle = (extraStyle ?? const TextStyle()).copyWith(
      fontFamily: 'serif',
      fontFamilyFallback: const ['Georgia', 'Times New Roman', 'serif'],
    );
    spans.add(TextSpan(text: match.group(0), style: latinStyle));
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: extraStyle));
  }
  return spans;
}

List<InlineSpan> _parseInline(
  String input, {
  required TextStyle baseStyle,
  required ThemeData theme,
  required FrostedTheme glass,
  required bool isCoffeePaper,
  required bool mixedLatinSerif,
}) {
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in _inlineTokenRe.allMatches(input)) {
    if (match.start > cursor) {
      spans.addAll(_styledTextSpans(
        input.substring(cursor, match.start),
        mixedLatinSerif: mixedLatinSerif,
      ));
    }

    final code = match.group(1);
    final boldItalic = match.group(2);
    final bold = match.group(3);
    final strike = match.group(4);
    final linkLabel = match.group(5);
    final italic = match.group(7);

    if (code != null) {
      spans.add(
        TextSpan(
          text: '\u2009$code\u2009',
          style: TextStyle(
            fontSize: (baseStyle.fontSize ?? 15) - 1.5,
            fontFamily: 'monospace',
            fontFamilyFallback: zhFallback,
            color: theme.colorScheme.onSurface,
            backgroundColor: isCoffeePaper
                ? const Color(0xFFEFEDE6)
                : theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
      );
    } else if (boldItalic != null) {
      spans.addAll(_styledTextSpans(
        boldItalic.trim(),
        extraStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontStyle: FontStyle.italic,
        ),
        mixedLatinSerif: mixedLatinSerif,
      ));
    } else if (bold != null) {
      spans.addAll(_styledTextSpans(
        bold.trim(),
        extraStyle: const TextStyle(fontWeight: FontWeight.w700),
        mixedLatinSerif: mixedLatinSerif,
      ));
    } else if (strike != null) {
      spans.addAll(_styledTextSpans(
        strike,
        extraStyle: TextStyle(
          decoration: TextDecoration.lineThrough,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        mixedLatinSerif: mixedLatinSerif,
      ));
    } else if (linkLabel != null) {
      spans.addAll(_styledTextSpans(
        linkLabel,
        extraStyle: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary.withValues(alpha: 0.45),
        ),
        mixedLatinSerif: mixedLatinSerif,
      ));
    } else if (italic != null) {
      spans.addAll(_styledTextSpans(
        italic,
        extraStyle: const TextStyle(fontStyle: FontStyle.italic),
        mixedLatinSerif: mixedLatinSerif,
      ));
    }

    cursor = match.end;
  }

  if (cursor < input.length) {
    spans.addAll(_styledTextSpans(
      input.substring(cursor),
      mixedLatinSerif: mixedLatinSerif,
    ));
  }

  return spans;
}
