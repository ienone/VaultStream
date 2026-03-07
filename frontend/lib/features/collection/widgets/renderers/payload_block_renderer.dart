import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:frontend/core/utils/safe_url_launcher.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/network/image_headers.dart';
import '../../models/content.dart';

class PayloadBlockRenderer extends ConsumerWidget {
  final ContentDetail content;

  const PayloadBlockRenderer({super.key, required this.content});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = content.richPayload;
    if (payload == null) return const SizedBox.shrink();

    final dio = ref.read(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    final List<Widget> children = [];

    // 1. 渲染 Quoted Content (Telegram/Twitter)
    final quotedRaw = payload['quoted_content'];
    if (quotedRaw is Map) {
      final quoteMap = Map<String, dynamic>.from(quotedRaw);
      children.add(_buildQuotedContent(context, quoteMap, apiBaseUrl, apiToken));
    }

    // 2. 渲染动态 Blocks (Zhihu Top Answers 等)
    final blocksRaw = payload['blocks'];
    if (blocksRaw is List && blocksRaw.isNotEmpty) {
      for (var block in blocksRaw) {
        if (block is! Map) continue;
        final blockMap = Map<String, dynamic>.from(block);
        final type = blockMap['type'] as String?;
        final dataRaw = blockMap['data'];
        final data = dataRaw is Map ? Map<String, dynamic>.from(dataRaw) : null;

        if (type == 'sub_item' && data != null) {
          children.add(_buildSubItem(context, data, apiBaseUrl, apiToken));
        }
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildQuotedContent(BuildContext context, Map<String, dynamic> quote, String apiBaseUrl, String? apiToken) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quoteUrl = quote['url']?.toString();
    final author = quote['author']?.toString();
    final text = quote['text']?.toString() ?? '';
    final thumbnail = quote['thumbnail']?.toString();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (quoteUrl != null && quoteUrl.isNotEmpty) {
              SafeUrlLauncher.openExternal(context, quoteUrl);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (author != null && author.isNotEmpty) ? author : '引用内容',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (thumbnail != null && thumbnail.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: thumbnail,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      httpHeaders: buildImageHeaders(
                        imageUrl: thumbnail,
                        baseUrl: apiBaseUrl,
                        apiToken: apiToken,
                      ),
                      placeholder: (context, url) => Container(
                        width: 60,
                        height: 60,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubItem(BuildContext context, Map<String, dynamic> data, String apiBaseUrl, String? apiToken) {
    final title = data['title'] as String?;
    final authorName = data['author_name'] as String?;
    final authorAvatarUrl = data['author_avatar_url'] as String?;
    final excerpt = data['excerpt'] as String?;
    final url = data['url'] as String?;
    final voteupCount = data['voteup_count'] as int?;
    final coverUrl = data['cover_url'] as String?;

    if ((title == null || title.trim().isEmpty) &&
        (excerpt == null || excerpt.trim().isEmpty)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Helper to map URLs
    String? mapUrl(String? url, String apiBaseUrl) {
      if (url == null) return null;
      if (url.startsWith('http')) {
        return '$apiBaseUrl/proxy/image?url=${Uri.encodeComponent(url)}';
      }
      return url;
    }

    final mappedAvatarUrl = mapUrl(authorAvatarUrl, apiBaseUrl);
    final mappedCoverUrl = mapUrl(coverUrl, apiBaseUrl);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: url != null
            ? () async {
                await SafeUrlLauncher.openExternal(context, url);
              }
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author and Vote Info
              if (authorName != null || authorAvatarUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: [
                      if (mappedAvatarUrl != null)
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          backgroundImage: CachedNetworkImageProvider(
                            mappedAvatarUrl,
                            headers: buildImageHeaders(
                              imageUrl: mappedAvatarUrl,
                              baseUrl: apiBaseUrl,
                              apiToken: apiToken,
                            ),
                          ),
                        )
                      else
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Text(
                            (authorName?.isNotEmpty == true ? authorName! : '?').substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          authorName ?? '匿名用户',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (voteupCount != null && voteupCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.thumb_up_alt_outlined, size: 10, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                voteupCount > 1000 ? '${(voteupCount/1000).toStringAsFixed(1)}k' : '$voteupCount',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (excerpt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              excerpt,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (mappedCoverUrl != null)
                    const SizedBox(width: 16),
                  if (mappedCoverUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: mappedCoverUrl,
                        width: 80,
                        height: 60,
                        fit: BoxFit.cover,
                        httpHeaders: buildImageHeaders(
                          imageUrl: mappedCoverUrl,
                          baseUrl: apiBaseUrl,
                          apiToken: apiToken,
                        ),
                        placeholder: (context, url) => Container(
                          width: 80,
                          height: 60,
                          color: colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, url, error) => const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
