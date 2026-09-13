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

Future<void> showBatchActions(BuildContext context) {
  if (MediaQuery.sizeOf(context).width >= 600 &&
      MediaQuery.sizeOf(context).height >= 480) {
    return showDialog<void>(
      context: context,
      animationStyle: _surfaceAnimation(context),
      builder: (_) => const PredictiveBackDialog(
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          constraints: BoxConstraints(maxWidth: 480),
          child: BatchActionSheet(),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    enableDrag: false,
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: _surfaceAnimation(context),
    builder: (_) => const SafeArea(top: false, child: BatchActionSheet()),
  );
}

class BatchActionSheet extends ConsumerStatefulWidget {
  const BatchActionSheet({super.key});
  @override
  ConsumerState<BatchActionSheet> createState() => _BatchActionSheetState();
}

class _BatchActionSheetState extends ConsumerState<BatchActionSheet> {
  BatchActionResult? _result;
  String _completedLabel = '已更新';

  Future<void> _perform(
    Future<BatchActionResult> Function() action,
    String label,
  ) async {
    if (ref.read(batchSelectionProvider).isProcessing) return;
    setState(() {
      _result = null;
      _completedLabel = label;
    });
    final result = await action();
    if (mounted) setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(batchSelectionProvider);
    final scheme = Theme.of(context).colorScheme;
    final done = _result != null && !_result!.hasFailures;
    final enabled = !selection.isProcessing && selection.count > 0;
    final actions = ref.read(batchSelectionProvider.notifier);
    return PopScope(
      canPop: !selection.isProcessing,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    done ? '处理完成' : '已选择 ${selection.count} 项',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭批量操作',
                  onPressed: selection.isProcessing
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (selection.isProcessing) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (selection.isProcessing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('正在处理，请稍候。'),
                    ),
                  if (_result case final result?)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          result.hasFailures
                              ? '$_completedLabel ${result.completed} 项，${result.failures.length} 项未完成。\n'
                                    '${result.failures.values.first}\n未完成的内容仍保持选中，可重试。'
                              : '$_completedLabel ${result.completed} 项。',
                          style: TextStyle(
                            color: result.hasFailures
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  if (!done) ...[
                    _action(
                      Icons.label_outline,
                      '替换标签',
                      '将选中内容统一设置为新的标签',
                      enabled ? _showTagEditor : null,
                    ),
                    _action(
                      Icons.eighteen_up_rating_outlined,
                      '标记为 NSFW',
                      null,
                      enabled
                          ? () => _perform(
                              () => actions.batchSetNsfw(true),
                              '已标记',
                            )
                          : null,
                    ),
                    _action(
                      Icons.verified_user_outlined,
                      '标记为安全',
                      null,
                      enabled
                          ? () => _perform(
                              () => actions.batchSetNsfw(false),
                              '已标记',
                            )
                          : null,
                    ),
                    _action(
                      Icons.refresh_rounded,
                      '重新解析',
                      '重新获取来源内容，后台继续处理',
                      enabled
                          ? () => _perform(actions.batchReParse, '已提交重新解析')
                          : null,
                    ),
                    const Divider(height: 24),
                    _action(
                      Icons.delete_outline_rounded,
                      '删除内容',
                      '永久删除选中的内容',
                      enabled ? _confirmDelete : null,
                      destructive: true,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: done
                        ? FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('完成'),
                          )
                        : TextButton(
                            onPressed: selection.isProcessing
                                ? null
                                : () {
                                    actions.clearSelection();
                                    Navigator.of(context).pop();
                                  },
                            child: const Text('取消选择'),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    IconData icon,
    String title,
    String? subtitle,
    VoidCallback? onTap, {
    bool destructive = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        enabled: onTap != null,
        shape: const RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Icon(
          icon,
          color: onTap == null
              ? scheme.onSurface.withValues(alpha: .38)
              : destructive
              ? scheme.error
              : scheme.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: destructive && onTap != null
              ? TextStyle(color: scheme.error)
              : null,
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        onTap: onTap,
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
