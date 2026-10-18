import 'package:flutter/cupertino.dart';
import '../theme/app_theme.dart';

/// Small, dependency-free Markdown renderer for notification bodies
/// (`note.md` / `dev-note.md`). Supports headings, lists, quotes, fenced code,
/// rules, links and **bold** / *italic* / `code` / ~~strike~~ inline spans.
class MarkdownView extends StatelessWidget {
  const MarkdownView(
    this.data, {
    super.key,
    this.baseSize = 14.5,
    this.color,
  });
  final String data;
  final double baseSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final label = color ?? CupertinoColors.label.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final accent = CupertinoTheme.of(context).primaryColor;
    final base = TextStyle(fontSize: baseSize, height: 1.62, color: label);
    final lines = data
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final blocks = <Widget>[];
    var i = 0;

    List<InlineSpan> inline(String text) => parseInline(
      text,
      base: base,
      accent: accent,
      codeColor: AppColors.raised.resolveFrom(context),
      secondary: secondary,
    );

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Fenced code block.
      if (trimmed.startsWith('```')) {
        final buffer = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          buffer.add(lines[i]);
          i++;
        }
        i++; // closing fence
        blocks.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.raised.resolveFrom(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: CupertinoColors.separator
                    .resolveFrom(context)
                    .withValues(alpha: dark ? .4 : .5),
                width: .5,
              ),
            ),
            child: Text(
              buffer.join('\n'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: baseSize - 1.5,
                height: 1.5,
                color: label,
              ),
            ),
          ),
        );
        continue;
      }

      // Heading.
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final size = switch (level) {
          1 => baseSize + 7,
          2 => baseSize + 4.5,
          3 => baseSize + 2.5,
          _ => baseSize + 1,
        };
        blocks.add(
          Padding(
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 8, bottom: 8),
            child: Text(
              heading.group(2)!.trim(),
              style: base.copyWith(
                fontSize: size,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        );
        i++;
        continue;
      }

      // Horizontal rule.
      if (RegExp(r'^\s*([-*_])\s*(\1\s*){2,}$').hasMatch(line)) {
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              height: .6,
              color: CupertinoColors.separator
                  .resolveFrom(context)
                  .withValues(alpha: dark ? .5 : .6),
            ),
          ),
        );
        i++;
        continue;
      }

      // Block quote.
      if (trimmed.startsWith('>')) {
        final buffer = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          buffer.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        blocks.add(
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: dark ? .10 : .06),
              border: Border(left: BorderSide(color: accent, width: 3)),
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(8),
              ),
            ),
            child: Text.rich(
              TextSpan(children: inline(buffer.join('\n'))),
              style: base.copyWith(color: secondary),
            ),
          ),
        );
        continue;
      }

      // Unordered list.
      if (RegExp(r'^\s*[-*+]\s+').hasMatch(line)) {
        final items = <String>[];
        while (i < lines.length && RegExp(r'^\s*[-*+]\s+').hasMatch(lines[i])) {
          items.add(lines[i].replaceFirst(RegExp(r'^\s*[-*+]\s+'), ''));
          i++;
        }
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1, right: 8),
                          child: Text(
                            '•',
                            style: base.copyWith(
                              color: secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text.rich(TextSpan(children: inline(item))),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
        continue;
      }

      // Ordered list.
      final ordered = RegExp(r'^\s*(\d+)[.)]\s+');
      if (ordered.hasMatch(line)) {
        final items = <String>[];
        while (i < lines.length && ordered.hasMatch(lines[i])) {
          items.add(lines[i].replaceFirst(ordered, ''));
          i++;
        }
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var n = 0; n < items.length; n++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          child: Text(
                            '${n + 1}.',
                            style: base.copyWith(color: secondary),
                          ),
                        ),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: inline(items[n])),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
        continue;
      }

      // Paragraph: consume until a blank line or another block start.
      final paragraph = <String>[];
      while (i < lines.length) {
        final current = lines[i];
        final t = current.trim();
        if (t.isEmpty ||
            t.startsWith('```') ||
            t.startsWith('>') ||
            RegExp(r'^#{1,6}\s').hasMatch(t) ||
            RegExp(r'^\s*[-*+]\s+').hasMatch(current) ||
            RegExp(r'^\s*\d+[.)]\s+').hasMatch(current) ||
            RegExp(r'^\s*([-*_])\s*(\1\s*){2,}$').hasMatch(current)) {
          break;
        }
        paragraph.add(t);
        i++;
      }
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(
            TextSpan(children: inline(paragraph.join(' '))),
            style: base,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}

/// Inline span parser: `**bold**`, `*italic*`, `` `code` ``, `~~strike~~`,
/// `[label](url)`.
List<InlineSpan> parseInline(
  String text, {
  required TextStyle base,
  required Color accent,
  required Color codeColor,
  required Color secondary,
}) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var i = 0;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(TextSpan(text: buffer.toString(), style: base));
    buffer.clear();
  }

  while (i < text.length) {
    final rest = text.substring(i);

    String? wrap(String marker, TextStyle style) {
      if (!rest.startsWith(marker)) return null;
      final end = text.indexOf(marker, i + marker.length);
      if (end <= i + marker.length) return null;
      final inner = text.substring(i + marker.length, end);
      flush();
      spans.add(TextSpan(text: inner, style: style));
      i = end + marker.length;
      return inner;
    }

    if (wrap('**', base.copyWith(fontWeight: FontWeight.w700)) != null) continue;
    if (wrap('__', base.copyWith(fontWeight: FontWeight.w700)) != null) continue;
    if (wrap('~~', base.copyWith(decoration: TextDecoration.lineThrough)) !=
        null) {
      continue;
    }
    if (wrap(
          '`',
          base.copyWith(
            fontFamily: 'monospace',
            fontSize: base.fontSize == null ? null : base.fontSize! - 1,
            backgroundColor: codeColor,
          ),
        ) !=
        null) {
      continue;
    }
    if (wrap('*', base.copyWith(fontStyle: FontStyle.italic)) != null) {
      continue;
    }
    if (wrap('_', base.copyWith(fontStyle: FontStyle.italic)) != null) {
      continue;
    }

    if (rest.startsWith('![') || rest.startsWith('[')) {
      final offset = rest.startsWith('![') ? 2 : 1;
      final close = text.indexOf(']', i + offset);
      if (close > i + offset && text.startsWith('(', close + 1)) {
        final end = text.indexOf(')', close + 2);
        if (end > close + 1) {
          final label = text.substring(i + offset, close);
          flush();
          spans.add(
            TextSpan(
              text: label,
              style: base.copyWith(
                color: accent,
                decoration: TextDecoration.underline,
                decorationColor: accent.withValues(alpha: .5),
              ),
            ),
          );
          i = end + 1;
          continue;
        }
      }
    }

    if (rest.startsWith('\\') && i + 1 < text.length) {
      buffer.write(text[i + 1]);
      i += 2;
      continue;
    }
    if (rest.startsWith('---') || rest.startsWith('***')) {
      // Not an inline rule; render literally.
      buffer.write(rest.substring(0, 3));
      i += 3;
      continue;
    }

    buffer.write(text[i]);
    i++;
  }
  flush();
  if (spans.isEmpty) spans.add(TextSpan(text: text, style: base.copyWith(color: secondary)));
  return spans;
}
