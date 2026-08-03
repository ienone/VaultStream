import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/image_headers.dart';
import '../../../../core/utils/media_utils.dart' as media_utils;
import '../../../../core/utils/safe_url_launcher.dart';
import '../../../../core/widgets/network_thumbnail.dart';
import '../../../../core/widgets/platform_badge.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/content.dart';
import '../../models/content_template.dart';
import '../../models/media_asset.dart';

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
    required this.apiBaseUrl,
    required this.apiToken,
    this.compact = false,
    this.showPlatform = true,
    this.showOriginalAction = true,
  });

  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
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
    final avatarCandidates = avatarAsset?.sources
        .map((source) => source.url)
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    final legacyAvatar = detail.authorAvatarUrl?.trim() ?? '';
    final avatarUrl =
        avatarCandidates?.firstOrNull ??
        (legacyAvatar.isEmpty
            ? null
            : media_utils.mapUrl(legacyAvatar, apiBaseUrl));

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showPlatform) PlatformBadge(platform: detail.platform),
        if (avatarUrl != null && avatarUrl.isNotEmpty)
          SizedBox.square(
            key: const ValueKey('content-detail-author-avatar'),
            dimension: compact ? 20 : 24,
            child: ClipOval(
              child: NetworkThumbnail(
                imageUrl: avatarUrl,
                fallbackUrls:
                    avatarCandidates?.skip(1).toList(growable: false) ??
                    const [],
                httpHeaders: avatarCandidates == null
                    ? buildImageHeaders(
                        imageUrl: avatarUrl,
                        baseUrl: apiBaseUrl,
                        apiToken: apiToken,
                      )
                    : null,
                fit: BoxFit.cover,
                maxHeightDiskCache: 128,
                errorIcon: Icons.person_rounded,
              ),
            ),
          ),
        Text(
          author.isEmpty ? '未知作者' : author,
          style: theme.textTheme.labelLarge?.copyWith(
            color: author.isEmpty ? scheme.onSurfaceVariant : scheme.onSurface,
            fontStyle: author.isEmpty ? FontStyle.italic : null,
          ),
        ),
        Text(
          DateFormat('yyyy-MM-dd HH:mm').format(published.toLocal()),
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (!compact && showOriginalAction)
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
  const ContentIdentityPanel({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    required this.apiToken,
  });

  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;

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
          PlatformBadge(platform: detail.platform),
          const SizedBox(height: AppSpacing.md),
          ContentSourceLine(
            detail: detail,
            apiBaseUrl: apiBaseUrl,
            apiToken: apiToken,
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
        message: '正文、媒体和派生结果可能尚未就绪。',
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
          if (action != null) action!,
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
              if (trailing != null) trailing!,
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
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppShape.paneBorder,
        border: Border.all(color: scheme.outlineVariant),
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
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 模板标识。当用户手动指定过模板时明确标注，避免被误认为自动判定。
class TemplateBadge extends StatelessWidget {
  const TemplateBadge({super.key, required this.detail});

  final ContentDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final manual = detail.hasManualTemplate;

    return Tooltip(
      message: manual ? '模板由你手动指定，重新解析不会覆盖' : '模板由系统根据来源和内容判定',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: manual
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppShape.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              manual ? Icons.push_pin_rounded : Icons.auto_mode_rounded,
              size: 12,
              color: manual
                  ? scheme.onSecondaryContainer
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              detail.template.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: manual
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
