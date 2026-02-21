import 'package:flutter/material.dart';
import 'package:frontend/core/utils/safe_url_launcher.dart';
import '../../models/content.dart';

class ContextCardRenderer extends StatelessWidget {
  final ContentDetail content;

  const ContextCardRenderer({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final contextData = content.contextData;
    if (contextData == null) return const SizedBox.shrink();

    final type = contextData['type'] as String?;
    final title = contextData['title'] as String?;
    final url = contextData['url'] as String?;
    final statsRaw = contextData['stats'];
    final Map<String, dynamic>? stats =
        statsRaw is Map ? Map<String, dynamic>.from(statsRaw) : null;

    if (type == 'question') {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 1,
        child: InkWell(
          onTap: url != null
              ? () async {
                  await SafeUrlLauncher.openExternal(context, url);
                }
              : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.help_outline,
                      size: 16,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '关联问题',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title ?? '未命名问题',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (stats != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    children: [
                      if (stats['answer_count'] != null)
                        _buildStat(context, '${stats['answer_count']} 回答'),
                      if (stats['follower_count'] != null)
                        _buildStat(context, '${stats['follower_count']} 关注'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildStat(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
    );
  }
}
