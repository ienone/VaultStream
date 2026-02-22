import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/constants/platform_constants.dart';
import '../../../models/content.dart';

class BvidCard extends StatelessWidget {
  final ContentDetail detail;

  const BvidCard({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    if (detail.platformId == null || !detail.platform.isBilibili) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 20,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: 12),
          Text(
            'BV号: ${detail.platformId}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 16),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: detail.platformId!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制 BV 号'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(Icons.copy, size: 16, color: colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
