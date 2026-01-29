import 'package:flutter/material.dart';
import 'package:frontend/core/utils/media_utils.dart';
import '../../../models/content.dart';
import 'unified_stat_item.dart';

class UnifiedStats extends StatelessWidget {
  final ContentDetail detail;
  final bool useContainer;

  const UnifiedStats({
    super.key,
    required this.detail,
    this.useContainer = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final stats = detail.extraStats;
    final bool isBilibili = detail.isBilibili;
    final bool isWeibo = detail.platform.toLowerCase() == 'weibo';
    final bool isZhihu = detail.isZhihu;
    final bool isXiaohongshu = detail.isXiaohongshu;
    final bool isUserProfile = detail.contentType == 'user_profile';
    final bool isColumn = detail.contentType == 'column';
    final bool isCollection = detail.contentType == 'collection';

    final List<Widget> items = [];

    if (isUserProfile) {
      if (isXiaohongshu) {
        // 小红书用户统计
        final xhsStats = stats.isNotEmpty ? stats : (detail.rawMetadata ?? {});
        final followers = xhsStats['followers'] ?? xhsStats['follower_count'] ?? 0;
        final following = xhsStats['following'] ?? xhsStats['following_count'] ?? 0;
        final liked = xhsStats['liked'] ?? xhsStats['liked_count'] ?? 0;
        
        if (followers is num && followers > 0) {
          items.add(
            UnifiedStatItem(
              icon: Icons.people_outline,
              label: '粉丝',
              value: formatCount(followers),
            ),
          );
        }
        if (following is num && following > 0) {
          items.add(
            UnifiedStatItem(
              icon: Icons.person_add_alt_1_outlined,
              label: '关注',
              value: formatCount(following),
            ),
          );
        }
        if (liked is num && liked > 0) {
          items.add(
            UnifiedStatItem(
              icon: Icons.thumb_up_alt_outlined,
              label: '获赞与收藏',
              value: formatCount(liked),
            ),
          );
        }
      } else if (isWeibo) {
        items.add(
          UnifiedStatItem(
            icon: Icons.people_outline,
            label: '粉丝',
            value: formatCount(detail.viewCount),
          ),
        );
        items.add(
          UnifiedStatItem(
            icon: Icons.person_add_alt_1_outlined,
            label: '关注',
            value: formatCount(detail.shareCount),
          ),
        );
        items.add(
          UnifiedStatItem(
            icon: Icons.article_outlined,
            label: '微博',
            value: formatCount(detail.commentCount),
          ),
        );
      } else if (isZhihu) {
        items.add(
          UnifiedStatItem(
            icon: Icons.people_outline,
            label: '粉丝',
            value: formatCount(detail.viewCount),
          ),
        );
        items.add(
          UnifiedStatItem(
            icon: Icons.person_add_alt_1_outlined,
            label: '关注',
            value: formatCount(detail.shareCount),
          ),
        );
        items.add(
          UnifiedStatItem(
            icon: Icons.thumb_up_alt_outlined,
            label: '获赞',
            value: formatCount(detail.likeCount),
          ),
        );
        items.add(
          UnifiedStatItem(
            icon: Icons.star_border,
            label: '收藏',
            value: formatCount(detail.collectCount),
          ),
        );
      }

      final Map<String, String> keyMap = {
        'thanked_count': '获谢',
        'answer_count': '回答',
        'articles_count': '文章',
        'pins_count': '想法',
        'question_count': '提问',
        'following_columns_count': '关注专栏',
        'following_topic_count': '关注话题',
        'following_favlists_count': '关注收藏夹',
        'statuses': '动态',
        'credit_score': '信用',
        'urank': '等级',
      };

      final Map<String, dynamic> combinedMetadata = {
        ...detail.extraStats,
        ...(detail.rawMetadata ?? {}),
      };

      for (var entry in combinedMetadata.entries) {
        if (keyMap.containsKey(entry.key) &&
            (entry.value is num && entry.value > 0)) {
          items.add(
            UnifiedStatItem(
              icon: Icons.analytics_outlined,
              label: keyMap[entry.key]!,
              value: formatCount(entry.value),
            ),
          );
        }
      }
    } else if (isColumn) {
      // 专栏统计
      items.add(
        UnifiedStatItem(
          icon: Icons.people_outline,
          label: '关注者',
          value: formatCount(detail.viewCount),
        ),
      );
      items.add(
        UnifiedStatItem(
          icon: Icons.article_outlined,
          label: '文章数',
          value: formatCount(detail.commentCount),
        ),
      );
      if (detail.likeCount > 0) {
        items.add(
          UnifiedStatItem(
            icon: Icons.thumb_up_alt_outlined,
            label: '获赞',
            value: formatCount(detail.likeCount),
          ),
        );
      }
    } else if (isCollection) {
      // 收藏夹统计
      items.add(
        UnifiedStatItem(
          icon: Icons.people_outline,
          label: '关注者',
          value: formatCount(detail.collectCount),
        ),
      );
      if (stats['item_count'] != null) {
        items.add(
          UnifiedStatItem(
            icon: Icons.bookmark_border,
            label: '内容数',
            value: formatCount(stats['item_count']),
          ),
        );
      }
      if (detail.viewCount > 0) {
        items.add(
          UnifiedStatItem(
            icon: Icons.remove_red_eye_outlined,
            label: '浏览',
            value: formatCount(detail.viewCount),
          ),
        );
      }
      if (detail.likeCount > 0) {
        items.add(
          UnifiedStatItem(
            icon: Icons.thumb_up_alt_outlined,
            label: '点赞',
            value: formatCount(detail.likeCount),
          ),
        );
      }
    } else {
      if (detail.viewCount > 0 || isBilibili) {
        items.add(
          UnifiedStatItem(
            icon: Icons.remove_red_eye_outlined,
            label: '浏览',
            value: formatCount(detail.viewCount),
          ),
        );
      }

      if (detail.likeCount > 0 || isZhihu || isBilibili || isXiaohongshu) {
        items.add(
          UnifiedStatItem(
            icon: isZhihu ? Icons.thumb_up_alt_outlined : Icons.favorite_border,
            label: isZhihu ? '赞同' : '点赞',
            value: formatCount(detail.likeCount),
          ),
        );
      }

      // 小红书：只有数值 > 0 才显示
      if (isXiaohongshu) {
        if (detail.collectCount > 0) {
          items.add(
            UnifiedStatItem(
              icon: Icons.star_border,
              label: '收藏',
              value: formatCount(detail.collectCount),
            ),
          );
        }
        if (detail.commentCount > 0) {
          items.add(
            UnifiedStatItem(
              icon: Icons.chat_bubble_outline,
              label: '评论',
              value: formatCount(detail.commentCount),
            ),
          );
        }
        if (detail.shareCount > 0) {
          items.add(
            UnifiedStatItem(
              icon: Icons.repeat_rounded,
              label: '分享',
              value: formatCount(detail.shareCount),
            ),
          );
        }
      } else {
        // 其他平台保持原有逻辑
        if (detail.collectCount > 0 || isBilibili || isZhihu) {
          items.add(
            UnifiedStatItem(
              icon: Icons.star_border,
              label: '收藏',
              value: formatCount(detail.collectCount),
            ),
          );
        }

        if (detail.commentCount > 0 || isBilibili || isWeibo || isZhihu) {
          items.add(
            UnifiedStatItem(
              icon: Icons.chat_bubble_outline,
              label: '评论',
              value: formatCount(detail.commentCount),
            ),
          );
        }

        if (detail.shareCount > 0 || isWeibo || isBilibili) {
          items.add(
            UnifiedStatItem(
              icon: Icons.repeat_rounded,
              label: isWeibo ? '转发' : '分享',
              value: formatCount(detail.shareCount),
            ),
          );
        }
      }

      if (detail.isZhihuQuestion) {
        if (stats['follower_count'] != null) {
          items.add(
            UnifiedStatItem(
              icon: Icons.person_add_alt,
              label: '关注',
              value: formatCount(stats['follower_count']),
            ),
          );
        }
        if (stats['visit_count'] != null && detail.viewCount == 0) {
          items.add(
            UnifiedStatItem(
              icon: Icons.remove_red_eye_outlined,
              label: '浏览',
              value: formatCount(stats['visit_count']),
            ),
          );
        }
        if (stats['answer_count'] != null) {
          items.add(
            UnifiedStatItem(
              icon: Icons.question_answer_outlined,
              label: '回答',
              value: formatCount(stats['answer_count']),
            ),
          );
        }
      }
    }

    if (items.isEmpty) return const SizedBox.shrink();

    final contentWidget = LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount = constraints.maxWidth > 600
            ? 4
            : (constraints.maxWidth > 360 ? 3 : 2);
        const double horizontalSpacing = 16.0;
        final double itemWidth =
            (constraints.maxWidth -
                (horizontalSpacing * (crossAxisCount - 1))) /
            crossAxisCount;

        return Wrap(
          spacing: horizontalSpacing,
          runSpacing: 24,
          children: items
              .map((item) => SizedBox(width: itemWidth, child: item))
              .toList(),
        );
      },
    );

    if (!useContainer) return contentWidget;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: contentWidget,
    );
  }
}
