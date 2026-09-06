import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../../core/utils/toast.dart';
import '../../../../../theme/design_tokens.dart';

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
        textStyle: (preferredStyle ?? appTheme.textTheme.bodyLarge)?.copyWith(
          color: appTheme.colorScheme.onSurface,
        ),
        onErrorFallback: (err) => Text(
          '\$$latex\$',
          style: (preferredStyle ?? appTheme.textTheme.bodyMedium)?.copyWith(
            color: appTheme.colorScheme.error,
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
          borderRadius: AppShape.cardBorder,
          border: Border.all(
            color: appTheme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            textContent,
            textStyle: (preferredStyle ?? appTheme.textTheme.titleMedium)
                ?.copyWith(color: appTheme.colorScheme.onSurface),
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
      // Inline code - 使用主题色系统确保在各种主题下都有良好的可见性
      // 暗色模式：使用 tertiaryContainer 作为背景，tertiary 作为文字（通常是高对比度的强调色）
      // 亮色模式：使用 primary 相关色
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: appTheme.colorScheme.surfaceContainerHigh,
          borderRadius: AppShape.cardMediaBorder,
        ),
        child: Text(
          textContent,
          style: GoogleFonts.firaCode(
            textStyle: appTheme.textTheme.bodySmall?.copyWith(
              color: appTheme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    // Block code - 使用 ClipRRect 确保内容不溢出
    return ClipRRect(
      borderRadius: AppShape.cardBorder,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: appTheme.colorScheme.surfaceContainerLow,
          borderRadius: AppShape.cardBorder,
          border: Border.all(color: appTheme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              decoration: BoxDecoration(
                color: appTheme.colorScheme.surfaceContainer,
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
                        Toast.show(
                          context,
                          '已复制代码',
                          icon: Icons.check_circle_outline_rounded,
                        );
                      },
                      borderRadius: AppShape.cardMediaBorder,
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
                              style: appTheme.textTheme.labelSmall?.copyWith(
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
                    textStyle: appTheme.textTheme.bodyMedium?.copyWith(
                      height: 1.6,
                      color: appTheme.colorScheme.onSurface,
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
