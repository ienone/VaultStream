import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bot_chat.dart';

class BotChatDialog extends ConsumerStatefulWidget {
  final BotChat? chat;
  final Function(BotChatCreate) onCreate;
  final Future<int> Function(String chatType) resolveBotConfigId;
  final Function(String, BotChatUpdate, String?)? onUpdate;

  const BotChatDialog({
    super.key,
    this.chat,
    required this.onCreate,
    required this.resolveBotConfigId,
    this.onUpdate,
  });

  @override
  ConsumerState<BotChatDialog> createState() => _BotChatDialogState();
}

class _BotChatDialogState extends ConsumerState<BotChatDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _chatIdController;
  late final TextEditingController _titleController;
  late final TextEditingController _nsfwChatIdController;

  late String _chatType;
  late bool _enabled;

  bool get isEditing => widget.chat != null;
  bool get _isQQType => _chatType == 'qq_group' || _chatType == 'qq_private';

  @override
  void initState() {
    super.initState();
    final chat = widget.chat;
    _chatType = chat?.chatType ?? 'channel';
    _chatIdController = TextEditingController(
      text: chat == null ? '' : _displayChatId(chat.chatId, _chatType),
    );
    _titleController = TextEditingController(text: chat?.title ?? '');
    _nsfwChatIdController =
        TextEditingController(text: chat?.nsfwChatId ?? '');
    _enabled = chat?.enabled ?? true;
  }

  @override
  void dispose() {
    _chatIdController.dispose();
    _titleController.dispose();
    _nsfwChatIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                        _buildExpressiveDropdown<String>(
                          label: '群组类型',
                          value: _chatType,
                          icon: Icons.category_rounded,
                          entries: const [
                            DropdownMenuEntry(value: 'channel', label: 'TG 频道'),
                            DropdownMenuEntry(value: 'group', label: 'TG 群组'),
                            DropdownMenuEntry(value: 'supergroup', label: 'TG 超级群组'),
                            DropdownMenuEntry(value: 'qq_group', label: 'QQ 群'),
                            DropdownMenuEntry(value: 'qq_private', label: 'QQ 私聊'),
                          ],
                          onChanged: (v) => setState(() => _chatType = v!),
                        ),
                        const SizedBox(height: 20),
                      ],
                      _buildTextField(
                        controller: _chatIdController,
                        label: _isQQType
                            ? (_chatType == 'qq_group' ? 'QQ 群号 *' : 'QQ 号 *')
                            : 'Chat ID *',
                        hint: _isQQType
                            ? (_chatType == 'qq_group' ? '例如: 123456789' : '对方的 QQ 号')
                            : '-1001234567890 或 @channel_name',
                        icon: _isQQType ? Icons.forum_rounded : Icons.alternate_email_rounded,
                        keyboardType: _isQQType ? TextInputType.number : null,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return _isQQType ? '请输入 QQ 号' : '请输入 Chat ID';
                          }
                          final raw = v.trim();
                          if (_isQQType) {
                            final candidate = raw.startsWith('group:') || raw.startsWith('private:')
                                ? raw.split(':').last
                                : raw;
                            if (int.tryParse(candidate) == null) {
                              return 'QQ 号必须为纯数字';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: _titleController,
                        label: '显示名称',
                        hint: '可选：群组/频道备注名称',
                        icon: Icons.title_rounded,
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: _nsfwChatIdController,
                        label: 'NSFW 备用频道 ID',
                        hint: '例如: -1001234567890（规则中 NSFW 策略为"分离"时使用）',
                        icon: Icons.call_split_rounded,
                      ),
                      const SizedBox(height: 24),
                      _buildSwitchTile(
                        title: '启用此配置',
                        subtitle: _isQQType
                            ? '控制是否向此 QQ 群/好友推送消息'
                            : '控制 Bot 是否向此群组/频道推送消息',
                        icon: Icons.power_settings_new_rounded,
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                      const SizedBox(height: 16),
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
                  onPressed: () => _submit(),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final normalizedChatId = _normalizeChatId(_chatIdController.text.trim());

    if (isEditing) {
      widget.onUpdate?.call(
        widget.chat!.chatId,
        BotChatUpdate(
          title:
              _titleController.text.isEmpty ? null : _titleController.text,
          enabled: _enabled,
          nsfwChatId: _nsfwChatIdController.text.isEmpty
              ? null
              : _nsfwChatIdController.text,
        ),
        normalizedChatId,
      );
    } else {
      final botConfigId = await widget.resolveBotConfigId(_chatType);
      widget.onCreate(
        BotChatCreate(
          botConfigId: botConfigId,
          chatId: normalizedChatId,
          chatType: _chatType,
          title:
              _titleController.text.isEmpty ? null : _titleController.text,
          enabled: _enabled,
          nsfwChatId: _nsfwChatIdController.text.isEmpty
              ? null
              : _nsfwChatIdController.text,
        ),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _normalizeChatId(String raw) {
    if (_chatType == 'qq_group') {
      if (raw.startsWith('group:')) return raw;
      return 'group:$raw';
    }
    if (_chatType == 'qq_private') {
      if (raw.startsWith('private:')) return raw;
      return 'private:$raw';
    }
    return raw;
  }

  String _displayChatId(String raw, String chatType) {
    if (chatType == 'qq_group' && raw.startsWith('group:')) {
      return raw.substring('group:'.length);
    }
    if (chatType == 'qq_private' && raw.startsWith('private:')) {
      return raw.substring('private:'.length);
    }
    return raw;
  }
}
