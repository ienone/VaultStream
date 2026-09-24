import 'parse_candidate_merge_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/safe_url_launcher.dart';
import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../core/widgets/platform_badge.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../models/content_template.dart';
import '../../../../core/media/media_asset.dart';

/// 内容详情的共享区块。
///
/// 所有模板复用这些区块表达相同语义（来源、标题、正文、派生结果、
/// 空状态与失败状态），模板之间的差异只体现在主体结构上。

/// 来源行：平台、作者、时间和原文入口。
///
/// 来源身份必须始终可见——这是判断"这条内容是什么、来自哪里"的依据。
class ContentSourceLine extends StatelessWidget {
  const ContentSourceLine({
    super.key,
    required this.detail,
    this.compact = false,
    this.showPlatform = true,
    this.showOriginalAction = true,
  });

  final ContentDetail detail;
  final bool compact;
  final bool showPlatform;
  final bool showOriginalAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final author = (detail.authorName ?? '').trim();
    final published = detail.publishedAt ?? detail.createdAt;
    final avatarAsset = detail.mediaAssets.firstFor(
      role: MediaRole.avatar,
      type: MediaType.image,
    );
    final avatarCandidates =
        avatarAsset?.sources
            .map((source) => source.url)
            .where((url) => url.isNotEmpty)
            .toList(growable: false) ??
        const [];
    final avatarUrl = avatarCandidates.firstOrNull;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showPlatform &&
            (detail.hasExternalOriginal || detail.platform == 'telegram'))
          PlatformBadge(platform: detail.platform),
        if (avatarUrl != null && avatarUrl.isNotEmpty)
          SizedBox.square(
            key: const ValueKey('content-detail-author-avatar'),
            dimension: compact ? 20 : 24,
            child: ClipOval(
              child: NetworkThumbnail(
                imageUrl: avatarUrl,
                fallbackUrls: avatarCandidates.skip(1).toList(growable: false),
                mediaAsset: avatarAsset,
                purpose: MediaPurpose.detail,
                fit: BoxFit.cover,
                maxHeightDiskCache: 128,
                errorIcon: Icons.person_rounded,
              ),
            ),
          ),
        if (author.isNotEmpty) Text(author, style: theme.textTheme.labelLarge),
        Text(
          DateFormat('yyyy-MM-dd HH:mm').format(published.toLocal()),
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (!compact && showOriginalAction && detail.hasExternalOriginal)
          TextButton.icon(
            onPressed: () => SafeUrlLauncher.openExternal(
              context,
              detail.externalOriginalUrl!,
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('原文'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
          ),
      ],
    );
  }
}

/// 宽屏辅助栏中的作者与来源信息。
///
/// 主详情头只承担内容身份；作者、时间等阅读上下文移到这里，避免标题区横向拥挤。
class ContentIdentityPanel extends StatelessWidget {
  const ContentIdentityPanel({super.key, required this.detail});

  final ContentDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('content-detail-identity-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ContentSourceLine(
            detail: detail,
            showPlatform: false,
            showOriginalAction: false,
          ),
        ],
      ),
    );
  }
}

/// 标题区块。标题缺失时显式说明，不用 URL 或正文片段冒充标题。
class ContentTitleBlock extends StatelessWidget {
  const ContentTitleBlock({
    super.key,
    required this.detail,
    this.titleOverride,
    this.style,
  });

  final ContentDetail detail;
  final String? titleOverride;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = (titleOverride ?? detail.title ?? '').trim();

    if (title.isEmpty || title == '-') {
      return const SizedBox.shrink();
    }

    return Text(
      title,
      style: (style ?? theme.textTheme.headlineSmall)?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }
}

/// 解析状态横幅。
///
/// 只呈现处理状态与重试操作；技术错误留在运行详情。
class ParseStatusBanner extends StatelessWidget {
  const ParseStatusBanner({super.key, required this.detail, this.onReParse});

  final ContentDetail detail;
  final VoidCallback? onReParse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (detail.isParseFailed) {
      return _Banner(
        icon: Icons.error_outline_rounded,
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        title: '解析失败',
        message: '',
        action: onReParse == null
            ? null
            : TextButton(onPressed: onReParse, child: const Text('重新解析')),
      );
    }

    if (detail.isParsePending) {
      return _Banner(
        icon: Icons.hourglass_top_rounded,
        background: scheme.surfaceContainerHigh,
        foreground: scheme.onSurface,
        title: detail.status == 'processing' ? '正在解析' : '等待解析',
        message: '',
      );
    }

    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppShape.paneBorder,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (message.isNotEmpty)
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground,
                    ),
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// 人工修订保护与重新解析候选。
///
/// 当前值和解析值始终并列呈现；任何按钮只处理一个字段，避免一次操作
/// 顺带接受尚未审阅的其他变化。
class ParseCandidatePanel extends StatefulWidget {
  const ParseCandidatePanel({
    super.key,
    required this.detail,
    required this.onResolve,
  });

  final ContentDetail detail;
  final Future<void> Function(String field, String action, String? mergedValue)
  onResolve;

  @override
  State<ParseCandidatePanel> createState() => _ParseCandidatePanelState();
}

class _ParseCandidatePanelState extends State<ParseCandidatePanel> {
  String? _busyField;

  static const _fieldLabels = {
    'title': '标题',
    'body': '正文',
    'author_name': '作者',
    'cover_url': '封面',
    'tags': '标签',
    'layout_type_override': '模板',
  };

  String? _currentValue(String field) => switch (field) {
    'title' => widget.detail.title,
    'body' => widget.detail.body,
    'author_name' => widget.detail.authorName,
    'cover_url' => widget.detail.coverUrl,
    _ => null,
  };

  Future<void> _resolve(
    String field,
    String action, [
    String? mergedValue,
  ]) async {
    if (_busyField != null) return;
    setState(() => _busyField = field);
    try {
      await widget.onResolve(field, action, mergedValue);
    } finally {
      if (mounted) setState(() => _busyField = null);
    }
  }

  Future<void> _merge(String field, String? parsedValue) async {
    final current = _currentValue(field) ?? '';
    final editor = ParseCandidateMergeEditor(
      field: field,
      label: _fieldLabels[field] ?? field,
      initialValue: current.isEmpty ? (parsedValue ?? '') : current,
      parsedValue: parsedValue,
    );
    final merged = field == 'body'
        ? await Navigator.of(
            context,
            rootNavigator: true,
          ).push<String>(MaterialPageRoute(builder: (_) => editor))
        : await showDialog<String>(
            context: context,
            animationStyle: MediaQuery.disableAnimationsOf(context)
                ? AnimationStyle.noAnimation
                : null,
            builder: (_) => editor,
          );
    if (merged != null && mounted) await _resolve(field, 'merge', merged);
  }

  static String _displayValue(String? value) {
    final normalized = (value ?? '').trim();
    return normalized.isEmpty ? '（空）' : normalized;
  }

  @override
  Widget build(BuildContext context) {
    final manualFields = widget.detail.manualEditFields;
    final candidate = widget.detail.parseCandidate;
    if (manualFields.isEmpty && candidate == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final candidateFields = candidate?.fields.entries.toList() ?? const [];
    return Container(
      key: const ValueKey('parse-candidate-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: candidate == null ? null : scheme.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                candidate == null
                    ? Icons.edit_note_rounded
                    : Icons.compare_arrows_rounded,
                color: scheme.tertiary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  candidate == null ? '人工修改已保护' : '发现新的解析结果',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (candidate != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              DateFormat('MM-dd HH:mm').format(candidate.createdAt.toLocal()),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (manualFields.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '已保护：${manualFields.map((field) => _fieldLabels[field] ?? field).join('、')}。重新解析不会自动覆盖。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (candidateFields.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final entry in candidateFields) ...[
              _CandidateFieldComparison(
                field: entry.key,
                label: _fieldLabels[entry.key] ?? entry.key,
                currentValue: _currentValue(entry.key),
                parsedValue: entry.value,
                busy: _busyField == entry.key,
                onAccept: () => _resolve(entry.key, 'accept_parsed'),
                onKeep: () => _resolve(entry.key, 'keep_current'),
                onMerge: entry.key == 'cover_url'
                    ? null
                    : () => _merge(entry.key, entry.value),
              ),
              if (entry != candidateFields.last)
                const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ],
      ),
    );
  }
}

class _CandidateFieldComparison extends StatelessWidget {
  const _CandidateFieldComparison({
    required this.field,
    required this.label,
    required this.currentValue,
    required this.parsedValue,
    required this.busy,
    required this.onAccept,
    required this.onKeep,
    required this.onMerge,
  });

  final String field;
  final String label;
  final String? currentValue;
  final String? parsedValue;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onKeep;
  final VoidCallback? onMerge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget valuePane(String title, String? value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _ParseCandidatePanelState._displayValue(value),
          maxLines: field == 'body' ? 8 : 4,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return Padding(
      key: ValueKey('parse-candidate-field-$field'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final panes = [
                valuePane('当前人工版本', currentValue),
                valuePane('新解析版本', parsedValue),
              ];
              final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
              if (constraints.maxWidth >= 520 * textScale) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: panes.first),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: panes.last),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: panes.first),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(width: double.infinity, child: panes.last),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              FilledButton.tonal(
                key: ValueKey('parse-candidate-accept-$field'),
                onPressed: busy ? null : onAccept,
                child: Text(busy ? '处理中…' : '采用新解析'),
              ),
              OutlinedButton(
                key: ValueKey('parse-candidate-keep-$field'),
                onPressed: busy ? null : onKeep,
                child: const Text('保留当前'),
              ),
              if (onMerge != null)
                TextButton(
                  key: ValueKey('parse-candidate-merge-action-$field'),
                  onPressed: busy ? null : onMerge,
                  child: const Text('对照并合并'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 阅读前的 AI 概览；长摘要可展开，保持与原文的清晰边界。
class ContentSummaryBlock extends StatefulWidget {
  const ContentSummaryBlock({super.key, required this.detail});

  final ContentDetail detail;

  @override
  State<ContentSummaryBlock> createState() => _ContentSummaryBlockState();
}

class _ContentSummaryBlockState extends State<ContentSummaryBlock> {
  bool _expanded = false;

  bool _overflows = false;

  @override
  void didUpdateWidget(covariant ContentSummaryBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.id != widget.detail.id) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.detail.hasSummary) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final summary = widget.detail.summary!.trim();
    final style = theme.textTheme.bodyMedium?.copyWith(height: 1.6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppShape.cardBorder,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text('AI 摘要', style: theme.textTheme.labelLarge),
                  ),
                  if (_overflows)
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? '收起' : '展开'),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              if (_expanded)
                SelectableText(summary, style: style)
              else
                _SummaryOverflowObserver(
                  onOverflow: (value) {
                    if (mounted && value != _overflows) {
                      setState(() => _overflows = value);
                    }
                  },
                  child: Text(
                    summary,
                    style: style,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Observe the paragraph actually laid out, including late-loaded CJK fonts.
class _SummaryOverflowObserver extends SingleChildRenderObjectWidget {
  const _SummaryOverflowObserver({
    required this.onOverflow,
    required super.child,
  });
  final ValueChanged<bool> onOverflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _SummaryOverflowRenderObject(onOverflow);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _SummaryOverflowRenderObject renderObject,
  ) {
    renderObject.onOverflow = onOverflow;
  }
}

class _SummaryOverflowRenderObject extends RenderProxyBox {
  _SummaryOverflowRenderObject(this.onOverflow);
  ValueChanged<bool> onOverflow;
  bool? _lastOverflow;

  @override
  void performLayout() {
    super.performLayout();
    final paragraph = child;
    if (paragraph is! RenderParagraph) return;
    final overflow = paragraph.didExceedMaxLines;
    if (_lastOverflow == overflow) return;
    _lastOverflow = overflow;
    WidgetsBinding.instance.addPostFrameCallback((_) => onOverflow(overflow));
  }
}

/// 空状态。用于缺失正文、媒体或派生结果的显式说明。
class ContentEmptyState extends StatelessWidget {
  const ContentEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.md,
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 区块标题。用于详情页内部分组。
class DetailSectionHeader extends StatelessWidget {
  const DetailSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 模板标识。当用户手动指定过模板时明确标注，避免被误认为自动判定。
