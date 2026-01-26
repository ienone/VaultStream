import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/content.dart';
import '../../providers/collection_provider.dart';
import '../../utils/content_parser.dart';
import '../../../../core/network/api_client.dart';
import 'components/content_side_info_card.dart';
import 'components/rich_content.dart';

class ContentDetailSheet extends ConsumerWidget {
  final int contentId;

  const ContentDetailSheet({super.key, required this.contentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(contentDetailProvider(contentId));

    // 获取 API Base URL 用于映射媒体链接
    final dio = ref.watch(apiClientProvider);
    final apiBaseUrl = dio.options.baseUrl;
    final apiToken = dio.options.headers['X-API-Token']?.toString();

    return detailAsync.when(
      data: (detail) => _buildDetail(context, detail, apiBaseUrl, apiToken),
      loading: () => const SizedBox(
        height: 360,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => SizedBox(
        height: 240,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('加载失败: $err'),
              TextButton(
                onPressed: () =>
                    ref.invalidate(contentDetailProvider(contentId)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    ContentDetail detail,
    String apiBaseUrl,
    String? apiToken,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 10, bottom: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Header with Platform Icon and Title
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ContentParser.getPlatformIcon(detail.platform, 24),
                          const SizedBox(width: 12),
                          if (detail.platform.toLowerCase() != 'twitter' &&
                              detail.platform.toLowerCase() != 'x')
                            Expanded(
                              child: Text(
                                detail.title ?? '无标题内容',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            // For Twitter, display "推文" instead of the content snippet title
                            Text(
                              '推文',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 2. 核心信息卡片 (直接使用 plain 模式避免嵌套边框)
                      ContentSideInfoCard(
                        detail: detail,
                        useContainer: false,
                        padding: EdgeInsets.zero,
                      ),

                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 16),

                      // 3. RICH CONTENT
                      RichContent(
                        detail: detail,
                        apiBaseUrl: apiBaseUrl,
                        apiToken: apiToken,
                        headerKeys: const {},
                        hideZhihuHeader: true, // SideInfoCard 已经处理了
                        hideTopAnswers: true, // SideInfoCard 已经处理了
                      ),

                      const SizedBox(height: 24),

                      // 4. Bottom Actions
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => launchUrl(
                                Uri.parse(detail.url),
                                mode: LaunchMode.externalApplication,
                              ),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('原始链接'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                            onPressed: () {
                              // TODO: Share
                            },
                            icon: const Icon(Icons.share),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
