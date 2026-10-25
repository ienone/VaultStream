import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/diff.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';

import '../utils/reading_markdown_syntax.dart';
import '../utils/safe_url_launcher.dart';
import '../utils/toast.dart';

export '../utils/reading_markdown_syntax.dart';

Map<String, MarkdownElementBuilder> readingMarkdownBuilders(
  BuildContext context,
) => {
  'pre': _CodeBlockBuilder(),
  'math-inline': _MathBuilder(block: false),
  'math-block': _MathBuilder(block: true),
};

class HeaderBuilder extends MarkdownElementBuilder {
  final Map<String, GlobalKey> keys;
  final TextStyle? style;
  final Map<String, int> _occurrenceCount;

  HeaderBuilder(this.keys, this.style, this._occurrenceCount);

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = readingHeadingText(element);
    final count = _occurrenceCount[text] ?? 0;
    _occurrenceCount[text] = count + 1;
    final uniqueKey = '${text.length}:$text:$count';
    final key = keys.putIfAbsent(uniqueKey, () => GlobalKey());
    return Padding(
      key: key,
      padding: EdgeInsets.only(top: element.tag == 'h1' ? 24 : 16, bottom: 4),
      child: _ReadingHeading(element: element, style: style ?? preferredStyle),
    );
  }
}

class _ReadingHeading extends StatefulWidget {
  const _ReadingHeading({required this.element, required this.style});

  final md.Element element;
  final TextStyle? style;

  @override
  State<_ReadingHeading> createState() => _ReadingHeadingState();
}

class _ReadingHeadingState extends State<_ReadingHeading> {
  final _links = <md.Element, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _collectLinks();
  }

  @override
  void didUpdateWidget(covariant _ReadingHeading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.element, widget.element)) {
      _disposeLinks();
      _collectLinks();
    }
  }

  void _collectLinks() {
    void visit(md.Node node) {
      if (node is! md.Element) return;
      if (node.tag == 'a') {
        _links[node] = TapGestureRecognizer()
          ..onTap = () async {
            await SafeUrlLauncher.openExternal(
              context,
              node.attributes['href'],
            );
          };
      }
      for (final child in node.children ?? const <md.Node>[]) {
        visit(child);
      }
    }

    for (final node in readingHeadingNodes(widget.element)) {
      visit(node);
    }
  }

  void _disposeLinks() {
    for (final recognizer in _links.values) {
      recognizer.dispose();
    }
    _links.clear();
  }

  @override
  void dispose() {
    _disposeLinks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headingStyle = widget.style ?? theme.textTheme.titleLarge!;
    final mono = _codeStyle(context);

    InlineSpan span(
      md.Node node,
      TextStyle parent,
      TapGestureRecognizer? link,
    ) {
      if (node is! md.Element) {
        return TextSpan(
          text: node.textContent,
          style: parent,
          recognizer: link,
        );
      }
      final activeLink = _links[node] ?? link;
      final style = switch (node.tag) {
        'a' => parent.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        'code' => parent.copyWith(
          fontFamily: mono.fontFamily,
          fontFamilyFallback: mono.fontFamilyFallback,
          letterSpacing: 0,
        ),
        'em' => parent.copyWith(fontStyle: FontStyle.italic),
        'strong' => parent.copyWith(fontWeight: FontWeight.w700),
        'del' => parent.copyWith(decoration: TextDecoration.lineThrough),
        _ => parent,
      };
      if (node.tag == 'img') {
        return TextSpan(
          text: node.attributes['alt'] ?? '',
          style: style,
          recognizer: activeLink,
        );
      }
      if (node.tag == 'math-inline') {
        Widget math = Math.tex(
          node.textContent,
          mathStyle: MathStyle.text,
          textStyle: style,
          onErrorFallback: (_) => Text(node.textContent, style: style),
        );
        if (activeLink != null) {
          math = Semantics(
            link: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(onTap: activeLink.onTap, child: math),
            ),
          );
        }
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: math,
        );
      }
      return TextSpan(
        style: style,
        children: [
          for (final child in node.children ?? const <md.Node>[])
            span(child, style, activeLink),
        ],
      );
    }

    return Semantics(
      header: true,
      child: Text.rich(
        TextSpan(
          children: [
            for (final node in readingHeadingNodes(widget.element))
              span(node, headingStyle, null),
          ],
        ),
        style: headingStyle,
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final language = (code?.attributes['class'] ?? '')
        .replaceFirst(RegExp(r'^language-'), '')
        .trim();
    return ReadingCodeBlock(code: element.textContent, language: language);
  }
}

class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({required this.block});
  final bool block;

  @override
  bool isBlockElement() => block;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final math = Math.tex(
      element.textContent,
      mathStyle: block ? MathStyle.display : MathStyle.text,
      textStyle: Theme.of(context).textTheme.bodyLarge,
      onErrorFallback: (_) =>
          Text(element.textContent, style: _codeStyle(context)),
    );
    if (!block) {
      return Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: math,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: math,
      ),
    );
  }
}

TextStyle _codeStyle(BuildContext context) {
  final theme = Theme.of(context);
  return GoogleFonts.firaCode(textStyle: theme.textTheme.bodyMedium).copyWith(
    fontFamilyFallback: theme.textTheme.bodyMedium?.fontFamilyFallback,
    height: 1.65,
    letterSpacing: 0,
    color: theme.colorScheme.onSurface,
  );
}

final _highlight = Highlight()
  ..registerLanguages({
    'bash': langBash,
    'c': langC,
    'cpp': langCpp,
    'css': langCss,
    'dart': langDart,
    'diff': langDiff,
    'go': langGo,
    'java': langJava,
    'javascript': langJavascript,
    'json': langJson,
    'python': langPython,
    'rust': langRust,
    'sql': langSql,
    'typescript': langTypescript,
    'xml': langXml,
    'yaml': langYaml,
  });

/// Code is kept as text spans so selection, indentation and large text survive.
/// Syntax colours follow the active Material scheme, including dark themes.
class ReadingCodeBlock extends StatefulWidget {
  const ReadingCodeBlock({
    super.key,
    required this.code,
    required this.language,
  });
  final String code;
  final String language;

  @override
  State<ReadingCodeBlock> createState() => _ReadingCodeBlockState();
}

class _ReadingCodeBlockState extends State<ReadingCodeBlock> {
  final _scrollController = ScrollController();
  late TextSpan _text;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _highlightCode();
  }

  @override
  void didUpdateWidget(covariant ReadingCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language) {
      _highlightCode();
    }
  }

  void _highlightCode() {
    final scheme = Theme.of(context).colorScheme;
    final style = _codeStyle(context);
    // Markdown contributes one trailing line break to fenced code.
    final code = widget.code.replaceFirst(RegExp(r'\n$'), '');
    _text = TextSpan(text: code, style: style);
    final language = widget.language.toLowerCase();
    HighlightResult result;
    if (language.isEmpty && code.length <= 12000) {
      result = _highlight.highlightAuto(code, [
        'bash',
        'c',
        'cpp',
        'css',
        'dart',
        'diff',
        'go',
        'java',
        'javascript',
        'json',
        'python',
        'rust',
        'sql',
        'typescript',
        'xml',
        'yaml',
      ]);
      // Unlabelled diagrams and plain output should remain plain text.
      if (result.relevance < 6) return;
    } else {
      if (_highlight.getLanguage(language) == null) return;
      result = _highlight.highlight(code: code, language: language);
    }
    final renderer = TextSpanRenderer(style, {
      'root': style,
      'keyword': TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      'type': TextStyle(color: scheme.primary),
      'built_in': TextStyle(color: scheme.primary),
      'title': TextStyle(color: scheme.primary),
      'title.function': TextStyle(color: scheme.primary),
      'title.function.invoke': TextStyle(color: scheme.primary),
      'title.class': TextStyle(color: scheme.primary),
      'title.class.inherited': TextStyle(color: scheme.primary),
      'string': TextStyle(color: scheme.tertiary),
      'regexp': TextStyle(color: scheme.tertiary),
      'number': TextStyle(color: scheme.tertiary),
      'literal': TextStyle(color: scheme.tertiary),
      'attr': TextStyle(color: scheme.secondary),
      'variable.language': TextStyle(color: scheme.secondary),
      'variable.constant': TextStyle(color: scheme.secondary),
      'meta': TextStyle(color: scheme.secondary),
      'comment': TextStyle(color: scheme.onSurfaceVariant),
      'addition': TextStyle(
        color: scheme.onTertiaryContainer,
        backgroundColor: scheme.tertiaryContainer,
      ),
      'deletion': TextStyle(
        color: scheme.onErrorContainer,
        backgroundColor: scheme.errorContainer,
      ),
    });
    result.render(renderer);
    _text = renderer.span ?? _text;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectionContainer.disabled(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 4, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.language,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '复制代码',
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    onPressed: () async {
                      try {
                        await Clipboard.setData(
                          ClipboardData(text: widget.code),
                        );
                        if (context.mounted) Toast.show(context, '已复制代码');
                      } catch (_) {
                        if (context.mounted) Toast.show(context, '复制失败');
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SelectionContainer.maybeOf(context) == null
                  ? SelectionArea(child: Text.rich(_text))
                  : Text.rich(_text),
            ),
          ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet readingMarkdownStyle(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final body = theme.textTheme.bodyLarge?.copyWith(
    height: 1.7,
    letterSpacing: 0,
    color: scheme.onSurface,
  );
  TextStyle? heading(TextStyle? style) => style?.copyWith(
    height: 1.35,
    letterSpacing: 0,
    fontWeight: FontWeight.w700,
    color: scheme.onSurface,
  );
  return MarkdownStyleSheet(
    p: body,
    a: TextStyle(color: scheme.primary, decoration: TextDecoration.underline),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    h1: heading(theme.textTheme.headlineMedium),
    h2: heading(theme.textTheme.headlineSmall),
    h3: heading(theme.textTheme.titleLarge),
    h4: heading(theme.textTheme.titleMedium),
    h5: heading(theme.textTheme.titleSmall),
    h6: heading(theme.textTheme.titleSmall),
    textScaler: MediaQuery.textScalerOf(context),
    blockSpacing: 16,
    listIndent: 24,
    listBullet: body,
    blockquote: body?.copyWith(color: scheme.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
    blockquoteDecoration: BoxDecoration(
      border: BorderDirectional(
        start: BorderSide(color: scheme.outlineVariant, width: 3),
      ),
    ),
    code: _codeStyle(context).copyWith(
      backgroundColor: scheme.surfaceContainerHigh,
      fontSize: (body?.fontSize ?? 16) * 0.9,
    ),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableScrollbarThumbVisibility: true,
    tablePadding: const EdgeInsets.only(bottom: 12),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    tableBody: theme.textTheme.bodyMedium?.copyWith(
      height: 1.5,
      color: scheme.onSurface,
    ),
    tableHead: theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    ),
    tableHeadCellsDecoration: BoxDecoration(color: scheme.surfaceContainerHigh),
    tableCellsDecoration: BoxDecoration(color: scheme.surfaceContainerLow),
    tableBorder: TableBorder(
      horizontalInside: BorderSide(color: scheme.outlineVariant),
    ),
    codeblockPadding: EdgeInsets.zero,
    codeblockDecoration: const BoxDecoration(),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: scheme.outlineVariant)),
    ),
  );
}
