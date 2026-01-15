import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

class HeaderBuilder extends MarkdownElementBuilder {
  final Map<String, GlobalKey> keys;
  final TextStyle? style;
  final Map<String, int> _occurrenceCount = {};

  HeaderBuilder(this.keys, this.style);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    // 为重复的标题生成唯一标识符，防止 GlobalKey 冲突
    final count = _occurrenceCount[text] ?? 0;
    _occurrenceCount[text] = count + 1;
    final uniqueKey = count == 0 ? text : '$text-$count';

    final key = keys.putIfAbsent(uniqueKey, () => GlobalKey());
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: style ?? preferredStyle),
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var language = '';
    if (element.attributes['class'] != null) {
      String lg = element.attributes['class'] as String;
      if (lg.startsWith('language-')) {
        language = lg.substring(9);
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final appTheme = Theme.of(context);
    final textContent = element.textContent.trim();
    final isMultiLine = element.textContent.contains('\n');
    final isBlock = language.isNotEmpty || isMultiLine;

    // 处理行内 LaTeX (格式: ‹LATEX:encoded›)
    if (textContent.startsWith('‹LATEX:') && textContent.endsWith('›')) {
      final encoded = textContent.substring(7, textContent.length - 1);
      final latex = Uri.decodeComponent(encoded);
      return Math.tex(
        latex,
        textStyle: preferredStyle?.copyWith(
          fontSize: 16,
          color: appTheme.colorScheme.onSurface,
        ),
        onErrorFallback: (err) => Text(
          '\$$latex\$',
          style: preferredStyle?.copyWith(
            color: appTheme.colorScheme.error,
            fontSize: 14,
          ),
        ),
      );
    }

    // 处理 LaTeX 代码块
    if (language == 'latex') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: appTheme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: appTheme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            textContent,
            textStyle: preferredStyle?.copyWith(
              fontSize: 20,
              color: appTheme.colorScheme.onSurface,
            ),
            onErrorFallback: (err) => Text(
              textContent,
              style: preferredStyle?.copyWith(
                color: appTheme.colorScheme.error,
              ),
            ),
          ),
        ),
      );
    }

    if (!isBlock) {
      // Inline code
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          textContent,
          style: GoogleFonts.firaCode(
            textStyle: TextStyle(
              fontSize: 13,
              color: isDark
                  ? appTheme.colorScheme.primaryContainer
                  : appTheme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    // Block code - 使用 ClipRRect 确保内容不溢出
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.02),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.code_rounded,
                    size: 14,
                    color: appTheme.colorScheme.primary.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  if (language.isNotEmpty)
                    Text(
                      language.toUpperCase(),
                      style: appTheme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        fontSize: 10,
                        color: appTheme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: element.textContent),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已复制代码'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.copy_all_rounded,
                              size: 14,
                              color: appTheme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '复制',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: appTheme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  element.textContent.trim(),
                  style: GoogleFonts.firaCode(
                    textStyle: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: isDark
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFF2D2D2D),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
