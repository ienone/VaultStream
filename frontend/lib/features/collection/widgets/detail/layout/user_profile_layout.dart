import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/network/image_headers.dart';
import '../../../models/content.dart';
import '../../../utils/content_parser.dart';
import '../components/unified_stats.dart';

class UserProfileLayout extends StatelessWidget {
  final ContentDetail detail;
  final String apiBaseUrl;
  final String? apiToken;
  final Function(List<String>, int) onImageTap;

  const UserProfileLayout({
    super.key,
    required this.detail,
    required this.apiBaseUrl,
    this.apiToken,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String imageUrl = detail.authorAvatarUrl ?? detail.coverUrl ?? '';
    final mappedAvatarUrl = ContentParser.mapUrl(imageUrl, apiBaseUrl);

    return Row(
      children: [
        // Left: Large Image Section
        Expanded(
          flex: 4,
          child: Container(
            color: colorScheme.surface,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  if (mappedAvatarUrl.isNotEmpty) {
                    onImageTap([mappedAvatarUrl], 0);
                  }
                },
                child: Hero(
                  tag: 'content-image-${detail.id}',
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: CachedNetworkImage(
                          imageUrl: mappedAvatarUrl,
                          httpHeaders: buildImageHeaders(
                            imageUrl: mappedAvatarUrl,
                            baseUrl: apiBaseUrl,
                            apiToken: apiToken,
                          ),
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              const CircularProgressIndicator(),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.person, size: 120),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Right: Information Card Section
        Expanded(
          flex: 6,
          child: Container(
            padding: const EdgeInsets.fromLTRB(0, 40, 40, 40),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 40,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: mappedAvatarUrl,
                            httpHeaders: buildImageHeaders(
                              imageUrl: mappedAvatarUrl,
                              baseUrl: apiBaseUrl,
                              apiToken: apiToken,
                            ),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () => _launchAuthorProfile(detail),
                                child: Text(
                                  detail.authorName ?? 'Unknown',
                                  style: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: colorScheme.onSurface,
                                    fontSize: 40,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  ContentParser.getPlatformIcon(
                                    detail.platform,
                                    18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    detail.platform.toUpperCase(),
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: colorScheme.outline,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2.0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    if (detail.description != null &&
                        detail.description!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          detail.description!,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    const SizedBox(height: 48),
                    UnifiedStats(detail: detail, useContainer: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
