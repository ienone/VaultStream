import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/batch_selection_provider.dart';
import '../../providers/collection_provider.dart';

class BatchActionSheet extends ConsumerWidget {
  const BatchActionSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(batchSelectionProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '已选择 ${selection.count} 项',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      ref.read(batchSelectionProvider.notifier).clearSelection();
                      Navigator.pop(context);
                    },
                    child: const Text('取消选择'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.label, color: colorScheme.primary),
              title: const Text('修改标签'),
              subtitle: const Text('为选中内容添加或修改标签'),
              onTap: () => _showTagEditor(context, ref),
            ),
            ListTile(
              leading: Icon(Icons.eighteen_up_rating, color: Colors.orange),
              title: const Text('标记为 NSFW'),
              onTap: () => _batchSetNsfw(context, ref, true),
            ),
            ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: const Text('标记为安全'),
              onTap: () => _batchSetNsfw(context, ref, false),
            ),
            ListTile(
              leading: Icon(Icons.refresh, color: colorScheme.tertiary),
              title: const Text('重新解析'),
              subtitle: const Text('重新获取内容元数据'),
              onTap: () => _batchReParse(context, ref),
            ),
            ListTile(
              leading: Icon(Icons.delete, color: colorScheme.error),
              title: Text('删除', style: TextStyle(color: colorScheme.error)),
              subtitle: const Text('永久删除选中内容'),
              onTap: () => _confirmBatchDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _showTagEditor(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改标签'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '标签 (逗号分隔)',
            hintText: '例如: 动画, 二次元, 搞笑',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context);

              final tags = controller.text
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();

              await ref.read(batchSelectionProvider.notifier).batchUpdateTags(tags);
              ref.invalidate(collectionProvider);
              ref.read(batchSelectionProvider.notifier).clearSelection();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('标签已更新')),
                );
              }
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }

  Future<void> _batchSetNsfw(BuildContext context, WidgetRef ref, bool isNsfw) async {
    Navigator.pop(context);

    await ref.read(batchSelectionProvider.notifier).batchSetNsfw(isNsfw);
    ref.invalidate(collectionProvider);
    ref.read(batchSelectionProvider.notifier).clearSelection();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isNsfw ? '已标记为 NSFW' : '已标记为安全')),
      );
    }
  }

  Future<void> _batchReParse(BuildContext context, WidgetRef ref) async {
    Navigator.pop(context);

    await ref.read(batchSelectionProvider.notifier).batchReParse();
    ref.invalidate(collectionProvider);
    ref.read(batchSelectionProvider.notifier).clearSelection();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已加入重新解析队列')),
      );
    }
  }

  void _confirmBatchDelete(BuildContext context, WidgetRef ref) {
    final selection = ref.read(batchSelectionProvider);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除这 ${selection.count} 项内容吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context);

              await ref.read(batchSelectionProvider.notifier).batchDelete();
              ref.invalidate(collectionProvider);
              ref.read(batchSelectionProvider.notifier).clearSelection();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已删除')),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
