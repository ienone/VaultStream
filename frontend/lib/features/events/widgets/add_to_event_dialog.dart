import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../theme/design_tokens.dart';
import '../providers/knowledge_event_provider.dart';

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
  int? _selectedEventId;
  String _role = 'source';
  String _evidenceState = 'unverified';
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.suggestedTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
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
    final events = ref.watch(activeKnowledgeEventsProvider);
    return AlertDialog(
      title: const Text('加入事件'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
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
                    onSelected: (_) => setState(() => _createNew = true),
                  ),
                  ChoiceChip(
                    label: const Text('加入已有事件'),
                    selected: !_createNew,
                    onSelected: (_) => setState(() => _createNew = false),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_createNew)
                TextField(
                  controller: _titleController,
                  autofocus: true,
                  maxLength: 240,
                  decoration: const InputDecoration(
                    labelText: '事件标题',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                events.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text(
                    formatApiErrorMessage(error, fallbackMessage: '无法读取已有事件'),
                  ),
                  data: (data) => data.items.isEmpty
                      ? const Text('还没有可加入的进行中事件，请先创建事件。')
                      : DropdownButtonFormField<int>(
                          initialValue: _selectedEventId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: '已有事件',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final event in data.items)
                              DropdownMenuItem(
                                value: event.id,
                                child: Text(
                                  event.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
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
                onChanged: (value) => setState(() => _role = value),
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
                onChanged: (value) => setState(() => _evidenceState = value),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? '正在保存' : '保存关系'),
        ),
      ],
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
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final entry in options.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
  );
}
