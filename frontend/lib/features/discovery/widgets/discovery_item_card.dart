import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:gap/gap.dart';
import '../models/discovery_models.dart';

class DiscoveryItemCard extends StatelessWidget {
  final DiscoveryItem item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isCompact;

  const DiscoveryItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isCompact = false,
  });

  Color _scoreColor(double score) {
    if (score >= 8) return Colors.green;
    if (score >= 6) return Colors.amber.shade700;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final score = item.aiScore;

    return Card(
      elevation: isSelected ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 10 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Score badge + Title
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (score != null) ...[
                    Container(
                      width: isCompact ? 32 : 36,
                      height: isCompact ? 32 : 36,
                      decoration: BoxDecoration(
                        color: _scoreColor(score).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        score.toStringAsFixed(1),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _scoreColor(score),
                          fontWeight: FontWeight.bold,
                          fontSize: isCompact ? 10 : 11,
                        ),
                      ),
                    ),
                    const Gap(8),
                  ],
                  Expanded(
                    child: Text(
                      item.title ?? item.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (isCompact
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.titleSmall)
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const Gap(6),
              // Row 2: Source type + relative time
              Row(
                children: [
                  if (item.sourceType != null) ...[
                    Icon(
                      _sourceIcon(item.sourceType!),
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const Gap(4),
                    Text(
                      item.sourceType!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Gap(8),
                  ],
                  Text(
                    timeago.format(
                      item.discoveredAt ?? item.createdAt,
                      locale: 'zh_CN',
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // Summary
              if (!isCompact &&
                  item.summary != null &&
                  item.summary!.isNotEmpty) ...[
                const Gap(6),
                Text(
                  item.summary!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _sourceIcon(String sourceType) {
    switch (sourceType.toLowerCase()) {
      case 'rss':
        return Icons.rss_feed_rounded;
      case 'hackernews' || 'hn':
        return Icons.whatshot_rounded;
      case 'reddit':
        return Icons.forum_rounded;
      default:
        return Icons.link_rounded;
    }
  }
}
