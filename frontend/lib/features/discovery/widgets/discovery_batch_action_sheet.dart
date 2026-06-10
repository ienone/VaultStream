import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/discovery_selection_provider.dart';
import '../providers/discovery_actions_provider.dart';
import '../../../core/utils/toast.dart';

class DiscoveryBatchActionSheet extends ConsumerWidget {
  final BuildContext parentContext;

  const DiscoveryBatchActionSheet({super.key, required this.parentContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(discoverySelectionProvider);
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
                      ref
                          .read(discoverySelectionProvider.notifier)
                          .clearSelection();
                      Navigator.pop(context);
                    },
                    child: const Text('取消选择'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.bookmark_add_rounded,
                color: colorScheme.primary,
              ),
              title: const Text('批量收藏'),
              subtitle: const Text('将选中内容加入收藏库'),
              onTap: () => _runBatchAction(context, ref, 'promote', '已批量收藏'),
            ),
            ListTile(
              leading: Icon(
                Icons.schedule_rounded,
                color: colorScheme.tertiary,
              ),
              title: const Text('批量稍后处理'),
              subtitle: const Text('保留候选，稍后继续人工决策'),
              onTap: () => _runBatchAction(context, ref, 'snooze', '已标记稍后处理'),
            ),
            ListTile(
              leading: Icon(
                Icons.visibility_off_rounded,
                color: colorScheme.error,
              ),
              title: const Text('批量忽略'),
              subtitle: const Text('忽略选中的发现内容'),
              onTap: () => _runBatchAction(context, ref, 'ignore', '已批量忽略'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runBatchAction(
    BuildContext sheetContext,
    WidgetRef ref,
    String action,
    String successMessage,
  ) async {
    final ids = Set<int>.from(ref.read(discoverySelectionProvider).selectedIds);
    final selectionNotifier = ref.read(discoverySelectionProvider.notifier);
    final actionsNotifier = ref.read(discoveryActionsProvider.notifier);
    Navigator.pop(sheetContext);

    try {
      await actionsNotifier.bulkAction(ids, action);
      selectionNotifier.clearSelection();
      if (parentContext.mounted) {
        Toast.show(
          parentContext,
          successMessage,
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } catch (e) {
      if (parentContext.mounted) {
        Toast.show(parentContext, '操作失败: $e', isError: true);
      }
    }
  }
}
