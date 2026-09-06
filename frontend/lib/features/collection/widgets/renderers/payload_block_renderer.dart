import 'package:flutter/material.dart';
import 'package:frontend/core/utils/safe_url_launcher.dart';
import 'package:frontend/core/media/media_asset.dart';
import 'package:frontend/core/widgets/network_thumbnail.dart';
import 'package:frontend/theme/design_tokens.dart';
import '../../models/content.dart';
import '../../utils/content_parser.dart';

class PayloadBlockRenderer extends StatelessWidget {
  final ContentDetail content;

  const PayloadBlockRenderer({super.key, required this.content});

  List<String> _imageCandidates(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return const [];
    return ContentParser.imageCandidatesForUrl(content, rawUrl);
  }

  @override
  Widget build(BuildContext context) {
    final payload = content.richPayload;
    if (payload == null) return const SizedBox.shrink();

    final List<Widget> children = [];

    // 1. 渲染 Quoted Content (Telegram/Twitter)
    final quotedRaw = payload['quoted_content'];
    if (quotedRaw is Map) {
      final quoteMap = Map<String, dynamic>.from(quotedRaw);
      children.add(_buildQuotedContent(context, quoteMap));
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
          children.add(_buildSubItem(context, data));
        }
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildQuotedContent(BuildContext context, Map<String, dynamic> quote) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quoteUrl = quote['url']?.toString();
    final author = quote['author']?.toString();
    final text = quote['text']?.toString() ?? '';
    final thumbnail = quote['thumbnail']?.toString();
    final thumbnailCandidates = _imageCandidates(thumbnail);
    final mappedThumbnail = thumbnailCandidates.firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: AppShape.cardMediaBorder,
        border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (quoteUrl != null && quoteUrl.isNotEmpty) {
              SafeUrlLauncher.openExternal(context, quoteUrl);
            }
          },
          borderRadius: AppShape.cardMediaBorder,
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
                if (mappedThumbnail != null && mappedThumbnail.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  NetworkThumbnail(
                    imageUrl: mappedThumbnail,
                    mediaAsset: ContentParser.imageAssetForUrl(
                      content,
                      thumbnail!,
                    ),
                    purpose: MediaPurpose.detail,
                    fallbackUrls: thumbnailCandidates
                        .skip(1)
                        .toList(growable: false),
                    width: 60,
                    height: 60,
                    borderRadius: AppShape.cardMediaBorder,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubItem(BuildContext context, Map<String, dynamic> data) {
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

    final avatarCandidates = _imageCandidates(authorAvatarUrl);
    final coverCandidates = _imageCandidates(coverUrl);
    final mappedAvatarUrl = avatarCandidates.firstOrNull;
    final mappedCoverUrl = coverCandidates.firstOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppShape.cardBorder,
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
        borderRadius: AppShape.cardBorder,
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
                        ClipOval(
                          child: NetworkThumbnail(
                            imageUrl: mappedAvatarUrl,
                            mediaAsset: ContentParser.imageAssetForUrl(
                              content,
                              authorAvatarUrl!,
                            ),
                            purpose: MediaPurpose.detail,
                            fallbackUrls: avatarCandidates
                                .skip(1)
                                .toList(growable: false),
                            width: 24,
                            height: 24,
                            errorIcon: Icons.person_outline_rounded,
                          ),
                        )
                      else
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Text(
                            (authorName?.isNotEmpty == true ? authorName! : '?')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppShape.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.thumb_up_alt_outlined,
                                size: 10,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                voteupCount > 1000
                                    ? '${(voteupCount / 1000).toStringAsFixed(1)}k'
                                    : '$voteupCount',
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
                  if (mappedCoverUrl != null) const SizedBox(width: 16),
                  if (mappedCoverUrl != null)
                    NetworkThumbnail(
                      imageUrl: mappedCoverUrl,
                      mediaAsset: ContentParser.imageAssetForUrl(
                        content,
                        coverUrl!,
                      ),
                      purpose: MediaPurpose.detail,
                      fallbackUrls: coverCandidates
                          .skip(1)
                          .toList(growable: false),
                      width: 80,
                      height: 60,
                      borderRadius: AppShape.cardMediaBorder,
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
