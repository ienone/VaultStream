import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/adaptive_form_dialog.dart';
import '../providers/bot_chats_provider.dart';
import '../providers/queue_provider.dart';

Future<void> showPushContentDialog(
  BuildContext context,
  List<int> contentIds,
) => showDialog<void>(
  context: context,
  barrierDismissible: true,
  builder: (_) =>
      _PushContentDialog(contentIds: contentIds, router: GoRouter.of(context)),
);

final manualPushProvider = Provider((ref) => ManualPushActions(ref));

class ManualPushActions {
  ManualPushActions(this.ref);
  final Ref ref;

  Future<({int sent, int skipped, List<String> errors})> send(
    List<int> contentIds,
    List<int> chatIds,
  ) async {
    final api = ref.read(apiClientProvider);
    final response = await api.post(
      '/distribution-queue/manual',
      data: {'content_ids': contentIds, 'bot_chat_ids': chatIds},
    );
    final data = response.data as Map<String, dynamic>;
    final ids = (data['item_ids'] as List).cast<int>();
    final results = await sendQueueItems(api, ids);
    return (
      sent: results.where((item) => item.sent).length,
      skipped: data['already_sent'] as int,
      errors: [
        for (final item in results)
          if (!item.sent) item.error ?? '尚未发送',
      ],
    );
  }
}

class _PushContentDialog extends ConsumerStatefulWidget {
  const _PushContentDialog({required this.contentIds, required this.router});
  final GoRouter router;
  final List<int> contentIds;
  @override
  ConsumerState<_PushContentDialog> createState() => _PushContentDialogState();
}

class _PushContentDialogState extends ConsumerState<_PushContentDialog> {
  final _selected = <int>{};
  bool _sending = false;
  bool _finished = false;
  bool _hasErrors = false;
  String? _message;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(manualPushProvider)
          .send(widget.contentIds, _selected.toList());
      if (!mounted) return;
      setState(() {
        _finished = true;
        _hasErrors = result.errors.isNotEmpty;
        _message = [
          '已发送 ${result.sent} 项',
          if (result.skipped > 0) '${result.skipped} 项已发送过，已跳过',
          if (result.errors.isNotEmpty)
            '${result.errors.length} 项未完成：${result.errors.first}',
        ].join('。');
      });
    } catch (error) {
      if (mounted) setState(() => _message = formatApiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AdaptiveFormDialog(
      title: '推送 ${widget.contentIds.length} 条内容',
      contentBuilder: (context, _, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_finished) ...[
            const Text('发送到'),
            ref
                .watch(botChatsProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => TextButton(
                    onPressed: () => ref.invalidate(botChatsProvider),
                    child: const Text('目标读取失败，重试'),
                  ),
                  data: (chats) {
                    final available = chats
                        .where(
                          (chat) =>
                              chat.enabled &&
                              chat.isAccessible &&
                              chat.isPushTarget,
                        )
                        .toList();
                    if (available.isEmpty) {
                      return TextButton.icon(
                        onPressed: () async {
                          await widget.router.push(
                            '/automation/distribution/targets',
                          );
                          ref.invalidate(botChatsProvider);
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('添加推送目标'),
                      );
                    }
                    return Column(
                      children: [
                        for (final chat in available)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(chat.displayName),
                            subtitle: Text(chat.chatTypeLabel),
                            value: _selected.contains(chat.id),
                            onChanged: _sending
                                ? null
                                : (value) => setState(() {
                                    value == true
                                        ? _selected.add(chat.id)
                                        : _selected.remove(chat.id);
                                  }),
                          ),
                      ],
                    );
                  },
                ),
          ],
          if (_sending) const LinearProgressIndicator(),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
        ],
      ),
      actions: OverflowBar(
        alignment: MainAxisAlignment.end,
        spacing: 8,
        children: [
          TextButton(
            onPressed: _sending ? null : () => Navigator.pop(context),
            child: Text(_finished ? '关闭' : '取消'),
          ),
          if (_finished)
            FilledButton.tonal(
              onPressed: () {
                Navigator.pop(context);
                widget.router.go(
                  _hasErrors
                      ? '/automation/distribution/history?status=filtered'
                      : '/automation/distribution/history',
                );
              },
              child: Text(_hasErrors ? '查看未发送' : '查看发送记录'),
            )
          else
            FilledButton(
              onPressed: _sending || _selected.isEmpty ? null : _send,
              child: Text(_sending ? '正在发送…' : '发送'),
            ),
        ],
      ),
    ),
  );
}
