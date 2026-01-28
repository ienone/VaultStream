import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bot_chat.dart';
import '../models/distribution_rule.dart';
import '../providers/distribution_rules_provider.dart';

class BotChatDialog extends ConsumerStatefulWidget {
  final BotChat? chat;
  final Function(BotChatCreate) onCreate;
  final Function(String, BotChatUpdate)? onUpdate;

  const BotChatDialog({
    super.key,
    this.chat,
    required this.onCreate,
    this.onUpdate,
  });

  @override
  ConsumerState<BotChatDialog> createState() => _BotChatDialogState();
}

class _BotChatDialogState extends ConsumerState<BotChatDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _chatIdController;
  late final TextEditingController _titleController;
  late final TextEditingController _priorityController;
  late final TextEditingController _tagFilterController;
  late final TextEditingController _nsfwChatIdController;

  late String _chatType;
  late String _nsfwPolicy;
  late bool _enabled;
  late List<int> _linkedRuleIds;

  bool get isEditing => widget.chat != null;

  @override
  void initState() {
    super.initState();
    final chat = widget.chat;
    _chatIdController = TextEditingController(text: chat?.chatId ?? '');
    _titleController = TextEditingController(text: chat?.title ?? '');
    _priorityController =
        TextEditingController(text: (chat?.priority ?? 0).toString());
    _tagFilterController =
        TextEditingController(text: chat?.tagFilter.join(', ') ?? '');
    _nsfwChatIdController =
        TextEditingController(text: chat?.nsfwChatId ?? '');
    _chatType = chat?.chatType ?? 'channel';
    _nsfwPolicy = chat?.nsfwPolicy ?? 'inherit';
    _enabled = chat?.enabled ?? true;
    _linkedRuleIds = List.from(chat?.linkedRuleIds ?? []);
  }

  @override
  void dispose() {
    _chatIdController.dispose();
    _titleController.dispose();
    _priorityController.dispose();
    _tagFilterController.dispose();
    _nsfwChatIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(distributionRulesProvider);

    return AlertDialog(
      title: Text(isEditing ? '编辑群组配置' : '添加 Bot 群组'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEditing) ...[
                  TextFormField(
                    controller: _chatIdController,
                    decoration: const InputDecoration(
                      labelText: 'Chat ID *',
                      hintText: '-1001234567890 或 @channel_name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? '请输入 Chat ID' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _chatType,
                    decoration: const InputDecoration(
                      labelText: '类型',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'channel', child: Text('频道')),
                      DropdownMenuItem(value: 'group', child: Text('群组')),
                      DropdownMenuItem(
                          value: 'supergroup', child: Text('超级群组')),
                    ],
                    onChanged: (v) => setState(() => _chatType = v!),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '显示名称',
                    hintText: '群组/频道名称',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priorityController,
                        decoration: const InputDecoration(
                          labelText: '优先级',
                          hintText: '0',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _nsfwPolicy,
                        decoration: const InputDecoration(
                          labelText: 'NSFW 策略',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'inherit', child: Text('继承全局')),
                          DropdownMenuItem(value: 'allow', child: Text('允许')),
                          DropdownMenuItem(value: 'block', child: Text('阻止')),
                          DropdownMenuItem(
                              value: 'separate', child: Text('分离频道')),
                        ],
                        onChanged: (v) => setState(() => _nsfwPolicy = v!),
                      ),
                    ),
                  ],
                ),
                if (_nsfwPolicy == 'separate') ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nsfwChatIdController,
                    decoration: const InputDecoration(
                      labelText: 'NSFW 备用频道 ID',
                      hintText: '-1001234567890',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tagFilterController,
                  decoration: const InputDecoration(
                    labelText: '标签过滤器',
                    hintText: '逗号分隔，留空接收所有',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('启用此群组'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                Text(
                  '关联分发规则',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                rulesAsync.when(
                  data: (rules) => _buildRuleSelector(rules),
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('加载规则失败: $e'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? '保存' : '添加'),
        ),
      ],
    );
  }

  Widget _buildRuleSelector(List<DistributionRule> rules) {
    if (rules.isEmpty) {
      return const Text('暂无可用规则');
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: rules.map((rule) {
        final isSelected = _linkedRuleIds.contains(rule.id);
        return FilterChip(
          label: Text(rule.name),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _linkedRuleIds.add(rule.id);
              } else {
                _linkedRuleIds.remove(rule.id);
              }
            });
          },
        );
      }).toList(),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final priority = int.tryParse(_priorityController.text) ?? 0;
    final tagFilter = _tagFilterController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (isEditing) {
      widget.onUpdate?.call(
        widget.chat!.chatId,
        BotChatUpdate(
          title:
              _titleController.text.isEmpty ? null : _titleController.text,
          enabled: _enabled,
          priority: priority,
          nsfwPolicy: _nsfwPolicy,
          nsfwChatId: _nsfwChatIdController.text.isEmpty
              ? null
              : _nsfwChatIdController.text,
          tagFilter: tagFilter,
          linkedRuleIds: _linkedRuleIds,
        ),
      );
    } else {
      widget.onCreate(
        BotChatCreate(
          chatId: _chatIdController.text,
          chatType: _chatType,
          title:
              _titleController.text.isEmpty ? null : _titleController.text,
          enabled: _enabled,
          priority: priority,
          nsfwPolicy: _nsfwPolicy,
          nsfwChatId: _nsfwChatIdController.text.isEmpty
              ? null
              : _nsfwChatIdController.text,
          tagFilter: tagFilter,
          linkedRuleIds: _linkedRuleIds,
        ),
      );
    }
    Navigator.of(context).pop();
  }
}
