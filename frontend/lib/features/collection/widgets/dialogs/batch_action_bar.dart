import '../../../automation/widgets/push_content_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/widgets/predictive_back_dialog.dart';
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
  Future<void> _perform(
    Future<BatchActionResult> Function() action,
    String label,
  ) async {
    if (ref.read(batchSelectionProvider).isProcessing) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await action();
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.hasFailures
              ? '$label ${result.completed} 项，${result.failures.length} 项未完成：${result.failures.values.first}'
              : '$label ${result.completed} 项',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(batchSelectionProvider);
    final scheme = Theme.of(context).colorScheme;
    final enabled = !selection.isProcessing && selection.count > 0;
    final actions = ref.read(batchSelectionProvider.notifier);
    final buttons =
        <({IconData icon, String label, VoidCallback? run, bool destructive})>[
          (
            icon: Icons.send_outlined,
            label: '推送',
            run: enabled
                ? () => showPushContentDialog(
                    context,
                    selection.selectedIds.toList(),
                  )
                : null,
            destructive: false,
          ),
          (
            icon: Icons.label_outline,
            label: '标签',
            run: enabled ? _showTagEditor : null,
            destructive: false,
          ),
          (
            icon: Icons.refresh_rounded,
            label: '重新解析',
            run: enabled
                ? () => _perform(actions.batchReParse, '已提交重新解析')
                : null,
            destructive: false,
          ),
          (
            icon: Icons.eighteen_up_rating_outlined,
            label: 'NSFW',
            run: enabled
                ? () => _perform(() => actions.batchSetNsfw(true), '已标记')
                : null,
            destructive: false,
          ),
          (
            icon: Icons.verified_user_outlined,
            label: '安全',
            run: enabled
                ? () => _perform(() => actions.batchSetNsfw(false), '已标记')
                : null,
            destructive: false,
          ),
          (
            icon: Icons.delete_outline,
            label: '删除',
            run: enabled ? _confirmDelete : null,
            destructive: true,
          ),
        ];
    final labelStyle = Theme.of(context).textTheme.labelLarge!;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final measure = TextPainter(
                text: TextSpan(text: '重新解析', style: labelStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final cellWidth = measure.width + 20 + 8 + 16;
              measure.dispose();
              final columns = constraints.maxWidth >= cellWidth * 6 ? 6 : 3;
              final stacked = constraints.maxWidth / columns < cellWidth;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 2,
                    child: selection.isProcessing
                        ? const LinearProgressIndicator()
                        : null,
                  ),
                  for (var start = 0; start < buttons.length; start += columns)
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final button
                              in buttons.skip(start).take(columns))
                            Expanded(
                              child: TextButton(
                                onPressed: button.run,
                                style: TextButton.styleFrom(
                                  foregroundColor: button.destructive
                                      ? scheme.error
                                      : null,
                                  minimumSize: const Size(0, 44),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  textStyle: labelStyle,
                                ),
                                child: stacked
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(button.icon, size: 20),
                                          const SizedBox(height: 4),
                                          Text(
                                            button.label,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(button.icon, size: 20),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              button.label,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            },
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
      builder: (context) => PredictiveBackDialog(
        child: AlertDialog(
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
  Widget build(BuildContext context) => PredictiveBackDialog(
    child: AlertDialog(
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
    ),
  );
}
