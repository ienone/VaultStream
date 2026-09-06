import 'package:flutter/material.dart';
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
        if (showPlatform && detail.hasExternalOriginal)
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
            onPressed: () => SafeUrlLauncher.openExternal(context, detail.url),
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
      return Text(
        '无标题',
        style: (style ?? theme.textTheme.headlineSmall)?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
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
/// 只在解析失败或仍在进行时出现。失败时展示后端记录的错误类型与
/// 失败次数，而不是笼统的"加载失败"。
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
        message: [
          if ((detail.lastErrorType ?? '').isNotEmpty) detail.lastErrorType!,
          if ((detail.lastError ?? '').isNotEmpty) detail.lastError!,
          if (detail.failureCount > 0) '已失败 ${detail.failureCount} 次',
        ].join(' · '),
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
    final merged = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _MergeCandidateDialog(
        field: field,
        label: _fieldLabels[field] ?? field,
        initialValue: current.isEmpty ? (parsedValue ?? '') : current,
        parsedValue: parsedValue,
      ),
    );
    if (merged != null && mounted) await _resolve(field, 'merge', merged);
  }

  static String _displayValue(String? value, {bool compact = false}) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return '（空）';
    if (!compact || normalized.length <= 120) return normalized;
    return '${normalized.substring(0, 120)}…';
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
        color: candidate == null
            ? scheme.surfaceContainerLow
            : scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: AppShape.paneBorder,
        border: Border.all(color: scheme.outlineVariant),
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
              if (candidate != null)
                Text(
                  DateFormat(
                    'MM-dd HH:mm',
                  ).format(candidate.createdAt.toLocal()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (manualFields.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '重新解析不会覆盖这些字段',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final field in manualFields)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_fieldLabels[field] ?? field),
                  ),
              ],
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

class _MergeCandidateDialog extends StatefulWidget {
  const _MergeCandidateDialog({
    required this.field,
    required this.label,
    required this.initialValue,
    required this.parsedValue,
  });

  final String field;
  final String label;
  final String initialValue;
  final String? parsedValue;

  @override
  State<_MergeCandidateDialog> createState() => _MergeCandidateDialogState();
}

class _MergeCandidateDialogState extends State<_MergeCandidateDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('合并${widget.label}'),
      content: SizedBox(
        width: 560,
        child: TextField(
          key: ValueKey('parse-candidate-merge-${widget.field}'),
          controller: _controller,
          autofocus: true,
          minLines: widget.field == 'body' ? 8 : 1,
          maxLines: widget.field == 'body' ? 18 : 4,
          decoration: InputDecoration(
            labelText: '最终保留的内容',
            helperText:
                '新解析：${_ParseCandidatePanelState._displayValue(widget.parsedValue, compact: true)}',
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('保存合并版本'),
        ),
      ],
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
    Widget valuePane(String title, String? value) => Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppShape.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            _ParseCandidatePanelState._displayValue(value),
            maxLines: field == 'body' ? 8 : 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    return Container(
      key: ValueKey('parse-candidate-field-$field'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: AppShape.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              final panes = [
                valuePane('当前人工版本', currentValue),
                valuePane('新解析版本', parsedValue),
              ];
              if (constraints.maxWidth >= 520) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: panes.first),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: panes.last),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(width: double.infinity, child: panes.first),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(width: double.infinity, child: panes.last),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
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
                  child: const Text('合并'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 派生结果容器。
///
/// 摘要、标签建议、评分等模型生成结果必须与原文有明确视觉边界，
/// 并标注来源，不能被当成来源事实展示。
class DerivedResultSection extends StatelessWidget {
  const DerivedResultSection({
    super.key,
    required this.title,
    required this.child,
    this.icon = Icons.auto_awesome_rounded,
    this.trailing,
  });

  final String title;
  final Widget child;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppShape.paneBorder,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.tertiary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '由模型生成，不是原文内容',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

/// AI 摘要区块。内容缺失时不渲染。
class ContentSummaryBlock extends StatelessWidget {
  const ContentSummaryBlock({super.key, required this.detail});

  final ContentDetail detail;

  @override
  Widget build(BuildContext context) {
    if (!detail.hasSummary) return const SizedBox.shrink();
    return DerivedResultSection(
      title: 'AI 摘要',
      child: SelectableText(
        detail.summary!.trim(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
      ),
    );
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
