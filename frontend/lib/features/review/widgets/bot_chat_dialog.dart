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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.smart_toy_rounded, color: colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Text(
                  isEditing ? '编辑群组配置' : '添加 Bot 群组',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isEditing) ...[
                        _buildTextField(
                          controller: _chatIdController,
                          label: 'Chat ID *',
                          hint: '-1001234567890 或 @channel_name',
                          icon: Icons.alternate_email_rounded,
                          validator: (v) => v == null || v.isEmpty ? '请输入 Chat ID' : null,
                        ),
                        const SizedBox(height: 20),
                        _buildExpressiveDropdown<String>(
                          label: '群组类型',
                          value: _chatType,
                          icon: Icons.category_rounded,
                          entries: const [
                            DropdownMenuEntry(value: 'channel', label: '频道'),
                            DropdownMenuEntry(value: 'group', label: '群组'),
                            DropdownMenuEntry(value: 'supergroup', label: '超级群组'),
                          ],
                          onChanged: (v) => setState(() => _chatType = v!),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildTextField(
                        controller: _titleController,
                        label: '显示名称',
                        hint: '可选：群组/频道备注名称',
                        icon: Icons.title_rounded,
                      ),
                      const SizedBox(height: 32),
                      _buildSubHeader('NSFW 与优先级'),
                      const SizedBox(height: 16),
                      _buildNsfwSelector(),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _priorityController,
                              label: '优先级',
                              hint: '0',
                              icon: Icons.priority_high_rounded,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _tagFilterController,
                              label: '标签过滤器',
                              hint: '逗号分隔，留空接收所有',
                              icon: Icons.filter_list_rounded,
                            ),
                          ),
                        ],
                      ),
                      if (_nsfwPolicy == 'separate') ...[
                        const SizedBox(height: 24),
                        _buildTextField(
                          controller: _nsfwChatIdController,
                          label: 'NSFW 备用频道 ID',
                          hint: '例如: -1001234567890',
                          icon: Icons.call_split_rounded,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _buildSwitchTile(
                        title: '启用此配置',
                        subtitle: '控制 Bot 是否向此群组/频道推送消息',
                        icon: Icons.power_settings_new_rounded,
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                      const SizedBox(height: 32),
                      _buildSubHeader('关联分发规则'),
                      const SizedBox(height: 16),
                      rulesAsync.when(
                        data: (rules) => _buildRuleSelector(rules),
                        loading: () => const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Text('加载失败: $e', style: TextStyle(color: colorScheme.error)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEditing ? '保存修改' : '确认添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildNsfwSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.security_rounded, size: 20, color: colorScheme.outline),
            const SizedBox(width: 12),
            Text('NSFW 策略', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'inherit', label: Text('继承'), icon: Icon(Icons.settings_backup_restore_rounded, size: 18)),
              ButtonSegment(value: 'allow', label: Text('允许'), icon: Icon(Icons.check_circle_outline_rounded, size: 18)),
              ButtonSegment(value: 'block', label: Text('阻止'), icon: Icon(Icons.block_rounded, size: 18)),
              ButtonSegment(value: 'separate', label: Text('分离'), icon: Icon(Icons.call_split_rounded, size: 18)),
            ],
            selected: {_nsfwPolicy},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() => _nsfwPolicy = newSelection.first);
            },
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.comfortable,
              selectedBackgroundColor: colorScheme.primary,
              selectedForegroundColor: colorScheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildExpressiveDropdown<T>({
    required String label,
    required T value,
    required IconData icon,
    required List<DropdownMenuEntry<T>> entries,
    required ValueChanged<T?> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return DropdownMenu<T>(
      initialSelection: value,
      dropdownMenuEntries: entries,
      onSelected: onChanged,
      leadingIcon: Icon(icon, size: 20),
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (value ? colorScheme.primary : colorScheme.outline).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: value ? colorScheme.primary : colorScheme.outline),
        ),
        value: value,
        onChanged: onChanged,
        thumbIcon: WidgetStateProperty.resolveWith<Icon?>((states) {
          if (states.contains(WidgetState.selected)) {
            return const Icon(Icons.check_rounded);
          }
          return const Icon(Icons.close_rounded);
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildRuleSelector(List<DistributionRule> rules) {
    if (rules.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('尚未创建任何分发规则', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          showCheckmark: true,
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
