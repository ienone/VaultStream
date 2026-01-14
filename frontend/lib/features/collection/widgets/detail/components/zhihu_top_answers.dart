import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../utils/content_parser.dart';
import '../../../utils/format_utils.dart';
import 'small_stat_item.dart';

class ZhihuTopAnswers extends ConsumerWidget {
  final List topAnswers;

  const ZhihuTopAnswers({super.key, required this.topAnswers});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (topAnswers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dio = ref.read(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 48),
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 20, color: colorScheme.primary),
            const SizedBox(width: 12),
            Text(
              "精选回答",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...topAnswers.map((ans) {
          if (ans == null) return const SizedBox.shrink();
          final authorName = ans['author_name'] ?? 'Unknown';
          final authorAvatar = ans['author_avatar_url'];
          final excerpt = ans['excerpt'] ?? '';
          final likeCount = ans['like_count'] ?? 0;
          final commentCount = ans['comment_count'] ?? 0;
          final url = ans['url'];
          final coverUrl = ans['cover_url'];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(
                24,
              ), // Large corners (Expressive)
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (url != null) {
                    launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (authorAvatar != null) ...[
                            CircleAvatar(
                              radius: 16,
                              backgroundImage: CachedNetworkImageProvider(
                                ContentParser.mapUrl(authorAvatar, apiBaseUrl),
                                headers: buildImageHeaders(
                                  imageUrl: ContentParser.mapUrl(
                                    authorAvatar,
                                    apiBaseUrl,
                                  ),
                                  baseUrl: apiBaseUrl,
                                  apiToken: apiToken,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              authorName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  excerpt,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    height: 1.6,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    SmallStatItem(
                                      icon: Icons.thumb_up_alt_outlined,
                                      label: '赞同',
                                      value: FormatUtils.formatCount(likeCount),
                                    ),
                                    const SizedBox(width: 16),
                                    SmallStatItem(
                                      icon: Icons.chat_bubble_outline,
                                      label: '评论',
                                      value: FormatUtils.formatCount(
                                        commentCount,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (coverUrl != null) ...[
                            const SizedBox(width: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedNetworkImage(
                                imageUrl: ContentParser.mapUrl(
                                  coverUrl,
                                  apiBaseUrl,
                                ),
                                httpHeaders: buildImageHeaders(
                                  imageUrl: ContentParser.mapUrl(
                                    coverUrl,
                                    apiBaseUrl,
                                  ),
                                  baseUrl: apiBaseUrl,
                                  apiToken: apiToken,
                                ),
                                width: 96,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
