import 'package:markdown/markdown.dart' as md;

List<md.InlineSyntax> readingInlineSyntaxes() => [_InlineMathSyntax()];

List<md.BlockSyntax> readingBlockSyntaxes() => [const _DisplayMathSyntax()];

/// Omit only a heading's generated permalink, never a literal C# or other text.
List<md.Node> readingHeadingNodes(md.Element heading) {
  final children = [...?heading.children];
  while (children.isNotEmpty &&
      children.last is md.Text &&
      children.last.textContent.trim().isEmpty) {
    children.removeLast();
  }
  if (children.lastOrNull case final md.Element link
      when link.tag == 'a' &&
          const ['#', '¶'].contains(link.textContent.trim()) &&
          (link.attributes['href']?.contains('#') ?? false)) {
    children.removeLast();
  }
  return children;
}

String readingHeadingText(md.Element heading) {
  String text(md.Node node) {
    if (node is! md.Element) return node.textContent;
    if (node.tag == 'img') return node.attributes['alt'] ?? '';
    return node.children?.map(text).join() ?? '';
  }

  return readingHeadingNodes(heading).map(text).join().trim();
}

class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax() : super(r'\$([^\$\n]+?)\$|\\\(([^\n]+?)\\\)');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final start = startMatchPos ?? parser.pos;
    final match = pattern.matchAsPrefix(parser.source, start);
    if (match == null) return false;
    final latex = match.group(1) ?? match.group(2)!;
    if (match.group(1) != null) {
      final before = start == 0 ? '' : parser.source[start - 1];
      final after = match.end == parser.source.length
          ? ''
          : parser.source[match.end];
      if (before == r'$' ||
          after == r'$' ||
          RegExp(r'\d').hasMatch(after) ||
          latex.trim() != latex ||
          (!latex.contains('\\') &&
              !RegExp(r'[=+^_{}]|^[a-zA-Z]$').hasMatch(latex))) {
        return false;
      }
    }
    // Rejecting in onMatch would leave the parser at the same position.
    return super.tryMatch(parser, start);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final latex = match.group(1) ?? match.group(2)!;
    parser.addNode(md.Element.text('math-inline', latex));
    return true;
  }
}

class _DisplayMathSyntax extends md.BlockSyntax {
  const _DisplayMathSyntax();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}(\$\$|\\\[|\\begin\{([a-zA-Z*]+)\})');

  String _closing(Match match) => switch (match.group(1)) {
    r'$$' => r'$$',
    r'\[' => r'\]',
    _ => '\\end{${match.group(2)}}',
  };

  @override
  bool canParse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content);
    if (match == null) return false;
    final closing = _closing(match);
    var offset = 0;
    while (true) {
      final line = parser.peek(offset);
      if (line == null) return false;
      final content = offset == 0
          ? line.content.substring(match.end)
          : line.content;
      final end = content.indexOf(closing);
      if (end >= 0) {
        // A math block owns complete lines. Leave prose after a closing
        // delimiter to the ordinary Markdown parser, without dropping it.
        return content.substring(end + closing.length).trim().isEmpty;
      }
      if (offset > 0 && RegExp(r'^ {0,3}(`{3,}|~{3,})').hasMatch(content)) {
        return false;
      }
      offset += 1;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content)!;
    final closing = _closing(match);
    final environment = match.group(2) != null;
    final lines = <String>[];
    var line = parser.current.content.substring(match.end);
    if (environment) lines.add(match.group(1)!);
    while (true) {
      final end = line.indexOf(closing);
      if (end >= 0) {
        lines.add(line.substring(0, end));
        if (environment) lines.add(closing);
        parser.advance();
        break;
      }
      lines.add(line);
      parser.advance();
      line = parser.current.content;
    }
    return md.Element.text('math-block', lines.join('\n').trim());
  }
}
