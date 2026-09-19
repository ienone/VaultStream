import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/adaptive_form_dialog.dart';
import '../../../theme/design_tokens.dart';
import '../models/queue_item.dart';
import '../providers/queue_provider.dart';

Future<void> showDeliveryReview(
  BuildContext context,
  WidgetRef ref,
  int itemId,
) async {
  try {
    final item = await ref.read(contentQueueProvider.notifier).loadItem(itemId);
    if (!context.mounted) return;
    if (!item.needsDeliveryReview) {
      Toast.show(context, '这条发送记录已处理，请刷新列表');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppMotion.surfaceEnter,
              reverseDuration: AppMotion.surfaceExit,
              curve: AppMotion.standardCurve,
            ),
      builder: (_) => DeliveryReviewDialog(item: item),
    );
  } catch (error) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(error, fallbackMessage: '读取待核对记录失败'),
      );
    }
  }
}

class DeliveryReviewDialog extends ConsumerStatefulWidget {
  const DeliveryReviewDialog({super.key, required this.item});
  final QueueItem item;

  @override
  ConsumerState<DeliveryReviewDialog> createState() =>
      _DeliveryReviewDialogState();
}

class _DeliveryReviewDialogState extends ConsumerState<DeliveryReviewDialog> {
  final _messageId = TextEditingController();
  bool? _delivered;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _messageId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting || _delivered == null) return;
    if (_delivered! && _messageId.text.trim().isEmpty) {
      setState(() => _error = '请填写在目标会话中核对到的消息 ID');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(contentQueueProvider.notifier)
          .reconcileDelivery(
            widget.item,
            delivered: _delivered!,
            messageId: _delivered! ? _messageId.text.trim() : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      Toast.show(context, _delivered! ? '已记录核对结果，未发送新消息' : '已确认未发送；需要时可另行排期');
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = formatApiErrorMessage(
            error,
            fallbackMessage: '保存失败，核对结果尚未确认',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: AdaptiveFormDialog(
      title: '核对发送结果',
      maxWidth: 520,
      contentBuilder: (context, width, short) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.item.title ?? '无标题内容',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(
            '目标：${widget.item.platform} · ${widget.item.targetId ?? '未知'}',
          ),
          if (widget.item.lastErrorAt case final occurred?)
            Text(
              '记录时间：${DateFormat('yyyy-MM-dd HH:mm').format(occurred.toLocal())}',
            ),
          const SizedBox(height: 16),
          const Text('平台可能已收到内容。请先打开目标会话核对，再记录结果；此操作不会发送或重发消息。'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('已找到消息'),
                selected: _delivered == true,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _delivered = true;
                        _error = null;
                      }),
              ),
              ChoiceChip(
                label: const Text('已核实未发送'),
                selected: _delivered == false,
                onSelected: _submitting
                    ? null
                    : (_) => setState(() {
                        _delivered = false;
                        _error = null;
                      }),
              ),
            ],
          ),
          if (_delivered == true) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _messageId,
              enabled: !_submitting,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '目标消息 ID',
                helperText: '以目标平台实际显示的消息 ID 为准',
              ),
            ),
          ],
          if (_delivered == false) ...[
            const SizedBox(height: 16),
            const Text('保存后仍不自动发送。如需发送，请返回队列单独恢复排期。'),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 8,
        children: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('暂不处理'),
          ),
          FilledButton(
            onPressed: _submitting || _delivered == null ? null : _save,
            child: Text(_submitting ? '正在保存…' : '保存核对结果'),
          ),
        ],
      ),
    ),
  );
}
