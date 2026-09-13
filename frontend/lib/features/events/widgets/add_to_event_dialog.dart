import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/discard_changes_dialog.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/adaptive_form_dialog.dart';
import '../../../core/widgets/browser_leave_guard.dart';
import '../models/knowledge_event.dart';
import '../../../theme/design_tokens.dart';
import '../providers/knowledge_event_provider.dart';

AnimationStyle _eventAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.surfaceEnter,
        reverseDuration: AppMotion.surfaceExit,
        curve: AppMotion.standardCurve,
      );

Future<KnowledgeEventDetail?> showAddToEventDialog(
  BuildContext context, {
  required int contentId,
  required String suggestedTitle,
}) => showDialog<KnowledgeEventDetail>(
  context: context,
  animationStyle: _eventAnimation(context),
  builder: (_) =>
      AddToEventDialog(contentId: contentId, suggestedTitle: suggestedTitle),
);

class AddToEventDialog extends ConsumerStatefulWidget {
  const AddToEventDialog({
    super.key,
    required this.contentId,
    required this.suggestedTitle,
  });

  final int contentId;
  final String suggestedTitle;

  @override
  ConsumerState<AddToEventDialog> createState() => _AddToEventDialogState();
}

class _AddToEventDialogState extends ConsumerState<AddToEventDialog> {
  late final TextEditingController _titleController;
  bool _createNew = true;
  bool _submitting = false;
  bool _confirmingExit = false;
  int? _selectedEventId;
  String _role = 'source';
  String _evidenceState = 'unverified';
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.suggestedTitle)
      ..addListener(_draftChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _draftChanged() => setState(() {});
  bool get _dirty =>
      _titleController.text != widget.suggestedTitle ||
      _selectedEventId != null ||
      _role != 'source' ||
      _evidenceState != 'unverified';
  Future<void> _requestClose() async {
    if (_submitting || _confirmingExit) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    _confirmingExit = true;
    final editingFocus = FocusManager.instance.primaryFocus;
    editingFocus?.unfocus();
    final discard = await showDiscardChangesDialog(
      context,
      title: '放弃未保存的修改？',
      message: '退出后，本次事件设置不会保存。',
      animationStyle: _eventAnimation(context),
    );
    _confirmingExit = false;
    if (!mounted) return;
    if (discard == true) {
      Navigator.pop(context);
    } else if (editingFocus?.context != null) {
      editingFocus!.requestFocus();
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final title = _titleController.text.trim();
    if (_createNew && title.isEmpty) {
      setState(() => _error = '请输入事件标题');
      return;
    }
    if (!_createNew && _selectedEventId == null) {
      setState(() => _error = '请选择一个事件');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final actions = ref.read(knowledgeEventActionsProvider);
      final event = _createNew
          ? await actions.createForContent(
              contentId: widget.contentId,
              title: title,
              role: _role,
              evidenceState: _evidenceState,
            )
          : await actions.addContent(
              eventId: _selectedEventId!,
              contentId: widget.contentId,
              role: _role,
              evidenceState: _evidenceState,
            );
      if (mounted) Navigator.pop(context, event);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = formatApiErrorMessage(error, fallbackMessage: '保存事件关系失败');
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _createNew ? null : ref.watch(activeKnowledgeEventsProvider);
    return BrowserLeaveGuard(
      enabled: _submitting || _dirty,
      child: PopScope<KnowledgeEventDetail>(
        canPop: !_submitting && !_dirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestClose();
        },
        child: AdaptiveFormDialog(
          title: '加入事件',
          contentBuilder: (context, width, short) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  ChoiceChip(
                    label: const Text('创建事件'),
                    selected: _createNew,
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() => _createNew = true),
                  ),
                  ChoiceChip(
                    label: const Text('加入已有事件'),
                    selected: !_createNew,
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() => _createNew = false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_createNew)
                TextField(
                  controller: _titleController,
                  enabled: !_submitting,
                  minLines: 1,
                  maxLines: short ? 1 : 3,
                  maxLength: 240,
                  decoration: const InputDecoration(labelText: '事件标题'),
                )
              else
                events!.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatApiErrorMessage(
                          error,
                          fallbackMessage: '无法读取已有事件',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            ref.invalidate(activeKnowledgeEventsProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                  data: (data) => data.items.isEmpty
                      ? const Text('还没有可加入的进行中事件，请先创建事件。')
                      : DropdownButtonFormField<int>(
                          initialValue:
                              data.items.any(
                                (event) => event.id == _selectedEventId,
                              )
                              ? _selectedEventId
                              : null,
                          borderRadius: AppShape.cardBorder,
                          dropdownColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHigh,
                          menuMaxHeight: 400,
                          itemHeight: null,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: '已有事件'),
                          items: [
                            for (final event in data.items)
                              DropdownMenuItem(
                                value: event.id,
                                child: Text(
                                  event.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _submitting
                              ? null
                              : (value) =>
                                    setState(() => _selectedEventId = value),
                        ),
                ),
              const SizedBox(height: AppSpacing.md),
              _EnumSelector(
                label: '内容角色',
                value: _role,
                options: const {
                  'source': '原始来源',
                  'report': '独立报道',
                  'commentary': '评论观点',
                  'background': '背景资料',
                  'correction': '更正信息',
                  'evidence': '现场证据',
                },
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _role = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              _EnumSelector(
                label: '证据状态',
                value: _evidenceState,
                options: const {
                  'unverified': '尚未确认',
                  'confirmed': '已确认',
                  'disputed': '存在争议',
                  'viewpoint': '观点',
                },
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _evidenceState = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
          actions: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting ? null : _requestClose,
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                  _submitting
                      ? '正在保存'
                      : _createNew
                      ? '创建并加入'
                      : '加入事件',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnumSelector extends StatelessWidget {
  const _EnumSelector({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    borderRadius: AppShape.cardBorder,
    dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    menuMaxHeight: 400,
    itemHeight: null,
    items: [
      for (final entry in options.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: onChanged == null
        ? null
        : (value) {
            if (value != null) onChanged!(value);
          },
  );
}
