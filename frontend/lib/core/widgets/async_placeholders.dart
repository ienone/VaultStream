import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 加载占位卡片，与业务无关。
///
/// ```dart
/// const LoadingPlaceholder(height: 240)
/// ```
class LoadingPlaceholder extends StatelessWidget {
  final double height;

  const LoadingPlaceholder({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(32),
      ),
      child: const Center(child: CircularProgressIndicator()),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 2.seconds);
  }
}

/// 错误提示卡片，适合嵌入列表/页面中展示简短错误信息。
///
/// 如需全屏错误或带重试按钮的复杂错误页，请在具体页面自行实现。
///
/// ```dart
/// ErrorCard(message: '加载队列失败: $e')
/// ```
class ErrorCard extends StatelessWidget {
  final String message;

  const ErrorCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: cs.error, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: cs.error)),
            ),
          ],
        ),
      ),
    );
  }
}
