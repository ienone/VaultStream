import '../../../../core/widgets/menu_back_scope.dart';
import '../../../../core/utils/toast.dart';
import '../../../automation/widgets/push_content_dialog.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/design_tokens.dart';
import '../../providers/batch_selection_provider.dart';

AnimationStyle _surfaceAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.surfaceEnter,
        reverseDuration: AppMotion.surfaceExit,
        curve: AppMotion.standardCurve,
      );

class BatchActionBar extends ConsumerStatefulWidget {
  const BatchActionBar({super.key});
  @override
  ConsumerState<BatchActionBar> createState() => _BatchActionBarState();
}

class _BatchActionBarState extends ConsumerState<BatchActionBar> {
  final _menuController = MenuController();
  bool _menuOpen = false;

  Future<void> _perform(
    Future<BatchActionResult> Function() action,
    String label,
  ) async {
    if (ref.read(batchSelectionProvider).isProcessing) return;
    final result = await action();
    if (!mounted) return;
    Toast.show(
      context,
      result.hasFailures
          ? '$label ${result.completed} 项，${result.failures.length} 项未完成：${result.failures.values.first}'
          : '$label ${result.completed} 项',
      isError: result.hasFailures,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(batchSelectionProvider);
    final enabled = !selection.isProcessing && selection.count > 0;
    final actions = ref.read(batchSelectionProvider.notifier);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selection.isProcessing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: enabled
                          ? () => showPushContentDialog(
                              context,
                              selection.selectedIds.toList(),
                            )
                          : null,
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('推送'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: enabled ? _showTagEditor : null,
                      icon: const Icon(Icons.label_outline),
                      label: const Text('标签'),
                    ),
                  ),
                  MenuBackScope(
                    open: _menuOpen,
                    close: _menuController.close,
                    child: MenuAnchor(
                      controller: _menuController,
                      animated: !MediaQuery.disableAnimationsOf(context),
                      onOpen: () => setState(() => _menuOpen = true),
                      onClose: () {
                        if (mounted) setState(() => _menuOpen = false);
                      },
                      menuChildren: [
                        MenuItemButton(
                          onPressed: enabled
                              ? () => _perform(actions.batchReParse, '已提交重新解析')
                              : null,
                          leadingIcon: const Icon(Icons.refresh_rounded),
                          child: const Text('重新解析'),
                        ),
                        MenuItemButton(
                          onPressed: enabled
                              ? () => _perform(
                                  () => actions.batchSetNsfw(true),
                                  '已标记',
                                )
                              : null,
                          leadingIcon: const Icon(
                            Icons.eighteen_up_rating_outlined,
                          ),
                          child: const Text('标记为敏感内容'),
                        ),
                        MenuItemButton(
                          onPressed: enabled
                              ? () => _perform(
                                  () => actions.batchSetNsfw(false),
                                  '已标记',
                                )
                              : null,
                          leadingIcon: const Icon(Icons.verified_user_outlined),
                          child: const Text('取消敏感标记'),
                        ),
                        const Divider(),
                        MenuItemButton(
                          onPressed: enabled ? _confirmDelete : null,
                          leadingIcon: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          child: const Text('删除'),
                        ),
                      ],
                      builder: (context, controller, _) => IconButton(
                        tooltip: '更多批量操作',
                        onPressed: enabled
                            ? () => controller.isOpen
                                  ? controller.close()
                                  : controller.open()
                            : null,
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
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

  Future<void> _showTagEditor() async {
    final tags = await showDialog<List<String>>(
      context: context,
      animationStyle: _surfaceAnimation(context),
      builder: (_) =>
          _BatchTagDialog(count: ref.read(batchSelectionProvider).count),
    );
    if (tags == null || !mounted) return;
    await _perform(
      () => ref.read(batchSelectionProvider.notifier).batchUpdateTags(tags),
      tags.isEmpty ? '已清空标签' : '已替换标签',
    );
  }

  Future<void> _confirmDelete() async {
    final count = ref.read(batchSelectionProvider).count;
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: _surfaceAnimation(context),
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text('删除 $count 项内容？'),
        content: const Text('内容及其独占的归档文件将被永久删除，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(
        ref.read(batchSelectionProvider.notifier).batchDelete,
        '已删除',
      );
    }
  }
}

class _BatchTagDialog extends StatefulWidget {
  const _BatchTagDialog({required this.count});
  final int count;
  @override
  State<_BatchTagDialog> createState() => _BatchTagDialogState();
}

class _BatchTagDialogState extends State<_BatchTagDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('替换标签'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('将替换选中 ${widget.count} 项内容的全部标签。留空会清空标签。'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '新的标签',
              hintText: '用逗号或换行分隔',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _controller.text
              .split(RegExp(r'[,，\n]'))
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toSet()
              .toList(),
        ),
        child: Text(_controller.text.trim().isEmpty ? '清空标签' : '替换标签'),
      ),
    ],
  );
}
