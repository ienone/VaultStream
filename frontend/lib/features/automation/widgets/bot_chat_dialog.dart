import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/adaptive_form_dialog.dart';
import '../../../core/utils/toast.dart';
import '../../../theme/design_tokens.dart';
import '../models/bot_chat.dart';

class BotChatDialog extends ConsumerStatefulWidget {
  final BotChat? chat;
  final Future<void> Function(BotChatCreate) onCreate;
  final Future<int> Function(String chatType) resolveBotConfigId;
  final Future<void> Function(int, BotChatUpdate, String?)? onUpdate;

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
    _nsfwChatIdController = TextEditingController(text: chat?.nsfwChatId ?? '');
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
    return AdaptiveFormDialog(
      title: isEditing ? '编辑推送目标' : '添加推送目标',
      contentBuilder: (context, width, short) => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isEditing) ...[
              _fieldLabel('目标类型'),
              const SizedBox(height: 8),
              Semantics(
                label: '目标类型',
                child: DropdownButtonFormField<String>(
                  initialValue: _chatType,
                  isExpanded: true,
                  itemHeight: null,
                  menuMaxHeight: 400,
                  borderRadius: AppShape.cardBorder,
                  dropdownColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHigh,
                  items: const [
                    DropdownMenuItem(value: 'channel', child: Text('TG 频道')),
                    DropdownMenuItem(value: 'group', child: Text('TG 群组')),
                    DropdownMenuItem(
                      value: 'supergroup',
                      child: Text('TG 超级群组'),
                    ),
                    DropdownMenuItem(value: 'qq_group', child: Text('QQ 群')),
                    DropdownMenuItem(value: 'qq_private', child: Text('QQ 私聊')),
                  ],
                  onTap: () => FocusScope.of(context).unfocus(),
                  onChanged: (value) {
                    if (value != null) setState(() => _chatType = value);
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
            _textField(
              controller: _chatIdController,
              label: _isQQType
                  ? (_chatType == 'qq_group' ? 'QQ 群号' : 'QQ 号')
                  : 'Chat ID',
              hint: _isQQType ? '例如：123456789' : '数字 ID 或 @名称',
              keyboardType: _isQQType ? TextInputType.number : null,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return _isQQType ? '请输入 QQ 号' : '请输入 Chat ID';
                }
                final raw = value.trim();
                if (_isQQType) {
                  final candidate =
                      raw.startsWith('group:') || raw.startsWith('private:')
                      ? raw.split(':').last
                      : raw;
                  if (int.tryParse(candidate) == null) return 'QQ 号必须为纯数字';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _textField(
              controller: _titleController,
              label: '显示名称（可选）',
              hint: '填写备注名称',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              shape: const RoundedRectangleBorder(
                borderRadius: AppShape.cardMediaBorder,
              ),
              contentPadding: EdgeInsets.zero,
              title: const Text('启用此目标'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('敏感内容分流'),
              subtitle: const Text('用于“分离”规则'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
              shape: const RoundedRectangleBorder(
                borderRadius: AppShape.cardMediaBorder,
              ),
              collapsedShape: const RoundedRectangleBorder(
                borderRadius: AppShape.cardMediaBorder,
              ),
              clipBehavior: Clip.antiAlias,
              initiallyExpanded: _nsfwChatIdController.text.isNotEmpty,
              maintainState: true,
              expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
                  ? AnimationStyle.noAnimation
                  : AnimationStyle(
                      duration: AppMotion.surfaceEnter,
                      reverseDuration: AppMotion.surfaceExit,
                      curve: AppMotion.standardCurve,
                    ),
              children: [
                _textField(
                  controller: _nsfwChatIdController,
                  label: '备用目标 ID',
                  hint: '填写目标 ID',
                ),
              ],
            ),
          ],
        ),
      ),
      actions: OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(isEditing ? '保存修改' : '添加'),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String label) =>
      Text(label, style: Theme.of(context).textTheme.bodyMedium);

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _fieldLabel(label),
      const SizedBox(height: 8),
      Semantics(
        label: label,
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintMaxLines: 2,
            errorMaxLines: 3,
          ),
        ),
      ),
    ],
  );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final normalizedChatId = _normalizeChatId(_chatIdController.text.trim());

      if (isEditing) {
        await widget.onUpdate?.call(
          widget.chat!.id,
          BotChatUpdate(
            title: _titleController.text.isEmpty ? null : _titleController.text,
            enabled: _enabled,
            nsfwChatId: _nsfwChatIdController.text.isEmpty
                ? null
                : _nsfwChatIdController.text,
          ),
          normalizedChatId,
        );
      } else {
        final botConfigId = await widget.resolveBotConfigId(_chatType);
        await widget.onCreate(
          BotChatCreate(
            botConfigId: botConfigId,
            chatId: normalizedChatId,
            chatType: _chatType,
            title: _titleController.text.isEmpty ? null : _titleController.text,
            enabled: _enabled,
            nsfwChatId: _nsfwChatIdController.text.isEmpty
                ? null
                : _nsfwChatIdController.text,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      Toast.show(context, '保存群组配置失败: $e', isError: true);
    }
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
