import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';

class AuthorHeader extends ConsumerWidget {
  final ContentDetail detail;

  const AuthorHeader({super.key, required this.detail});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isBilibili = detail.isBilibili;

    String? avatarUrl;
    if (detail.contentType == 'user_profile') {
      avatarUrl = detail.coverUrl;
    } else {
      if (detail.authorAvatarUrl != null) {
        avatarUrl = detail.authorAvatarUrl;
      } else {
        final rawAuthor = detail.rawMetadata?['author'];
        final rawUser = detail.rawMetadata?['user'];

        if (rawUser is Map) {
          avatarUrl = rawUser['avatar_hd'] ?? rawUser['profile_image_url'];
        } else if (rawAuthor is Map) {
          avatarUrl = rawAuthor['face'] ?? rawAuthor['avatarUrl'];
        }
      }
    }

    final dio = ref.read(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();
    final mappedAvatarUrl = avatarUrl != null
        ? ContentParser.mapUrl(avatarUrl, apiBaseUrl)
        : null;

    final String publishedStr = detail.publishedAt != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(detail.publishedAt!.toLocal())
        : DateFormat('yyyy-MM-dd HH:mm').format(detail.createdAt.toLocal());

    final bool isEdited =
        detail.updatedAt
            .difference(detail.publishedAt ?? detail.createdAt)
            .inMinutes
            .abs() >
        60;
    final String editedStr = isEdited
        ? DateFormat('yyyy-MM-dd HH:mm').format(detail.updatedAt.toLocal())
        : '';

    return GestureDetector(
      onTap: () => _launchAuthorProfile(detail),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isBilibili
                    ? [const Color(0xFFFB7299), const Color(0xFFFF9DB5)]
                    : [colorScheme.primary, colorScheme.tertiary],
              ),
            ),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: colorScheme.surface,
              backgroundImage: mappedAvatarUrl != null
                  ? CachedNetworkImageProvider(
                      mappedAvatarUrl,
                      headers: buildImageHeaders(
                        imageUrl: mappedAvatarUrl,
                        baseUrl: apiBaseUrl,
                        apiToken: apiToken,
                      ),
                    )
                  : null,
              child: mappedAvatarUrl == null
                  ? Text(
                      (detail.authorName ?? '?').substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: isBilibili
                            ? const Color(0xFFFB7299)
                            : colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      detail.authorName ?? '未知作者',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ContentParser.getPlatformIcon(detail.platform, 14),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      '发布于 $publishedStr',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isEdited)
                      Text(
                        '编辑于 $editedStr',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _launchAuthorProfile(ContentDetail detail) {
    if (detail.authorId != null && detail.authorId!.isNotEmpty) {
      String url;
      if (detail.isZhihu) {
        url = "https://www.zhihu.com/people/${detail.authorId}";
      } else if (detail.isBilibili) {
        url = "https://space.bilibili.com/${detail.authorId}";
      } else if (detail.isTwitter) {
        url = "https://twitter.com/i/user/${detail.authorId}";
      } else if (detail.isWeibo) {
        url = "https://weibo.com/u/${detail.authorId}";
      } else {
        return;
      }
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
