import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/widgets/discard_changes_dialog.dart';
import '../../../core/widgets/browser_leave_guard.dart';
import '../../../theme/design_tokens.dart';
import '../models/distribution_rule.dart';
import '../models/bot_chat.dart';
import '../models/render_config.dart';
import 'render_config_editor.dart';

class DistributionRuleEditor extends StatefulWidget {
  const DistributionRuleEditor({
    super.key,
    this.rule,
    required this.onSave,
    required this.onCancel,
    required this.onManageTargets,
    required this.availableChats,
    this.initialSelectedChatIds = const [],
  });
  final DistributionRule? rule;
  final Future<void> Function(DistributionRuleCreate, List<int>) onSave;
  final VoidCallback onCancel;
  final VoidCallback onManageTargets;
  final List<BotChat> availableChats;
  final List<int> initialSelectedChatIds;
  @override
  State<DistributionRuleEditor> createState() => DistributionRuleEditorState();
}

class DistributionRuleEditorState extends State<DistributionRuleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _include;
  late final TextEditingController _exclude;
  late final TextEditingController _description;
  late Set<int> _targets;
  late bool _enabled, _approval;
  late String _nsfw, _matchMode, _platform;
  late RenderConfig _render;
  late int _interval;
  late String _initialDraft;
  bool _saving = false, _exitAllowed = false, _confirming = false;
  String? _error;
  List<TextEditingController> get _controllers => [
    _name,
    _include,
    _exclude,
    _description,
  ];
  String _snapshot() => jsonEncode([
    for (final c in _controllers) c.text,
    _targets.toList()..sort(),
    _enabled,
    _approval,
    _nsfw,
    _matchMode,
    _platform,
    _render,
    _interval,
  ]);
  bool get _dirty => _snapshot() != _initialDraft;
  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    final conditions = rule?.matchConditions ?? {};
    _name = TextEditingController(text: rule?.name ?? '');
    _include = TextEditingController(
      text: (conditions['tags'] as List? ?? []).join('，'),
    );
    _exclude = TextEditingController(
      text: (conditions['tags_exclude'] as List? ?? []).join('，'),
    );
    _description = TextEditingController(text: rule?.description ?? '');
    _targets = widget.initialSelectedChatIds.toSet();
    _enabled = rule?.enabled ?? true;
    _approval = rule?.approvalRequired ?? false;
    _nsfw = rule?.nsfwPolicy ?? 'block';
    _matchMode = conditions['tags_match_mode'] as String? ?? 'any';
    _platform = conditions['platform'] as String? ?? '';
    _render = rule?.renderConfig ?? {};
    _interval =
        rule?.rateLimit != null &&
            rule!.rateLimit! > 0 &&
            rule.timeWindow != null
        ? -1
        : 0;
    _initialDraft = _snapshot();
    for (final c in _controllers) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void allowExitAfterSave() => setState(() => _exitAllowed = true);
  Future<bool> confirmExit() async {
    if (_exitAllowed) return true;
    if (_saving || _confirming) return false;
    if (!_dirty) return true;
    _confirming = true;
    final discard = await showDiscardChangesDialog(
      context,
      title: '放弃未保存的修改？',
      message: '退出后，本次修改不会保存。',
    );
    _confirming = false;
    if (discard == true && mounted) {
      setState(() => _exitAllowed = true);
      return true;
    }
    return false;
  }

  Future<void> _close() async {
    if (await confirmExit() && mounted) widget.onCancel();
  }

  List<String> _tags(String value) => value
      .split(RegExp(r'[,，\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_targets.isEmpty) {
      setState(() => _error = '请选择至少一个推送目标');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final conditions = <String, dynamic>{
      ...?widget.rule?.matchConditions,
      'tags': _tags(_include.text),
      'tags_exclude': _tags(_exclude.text),
      'tags_match_mode': _matchMode,
    };
    if (_platform.isEmpty) {
      conditions.remove('platform');
    } else {
      conditions['platform'] = _platform;
    }
    try {
      await widget.onSave(
        DistributionRuleCreate(
          name: _name.text.trim(),
          description: _description.text.trim(),
          matchConditions: conditions,
          enabled: _enabled,
          approvalRequired: _approval,
          nsfwPolicy: _nsfw,
          renderConfig: _render,
          priority: widget.rule?.priority ?? 0,
          templateId: widget.rule?.templateId,
          rateLimit: _interval == -1
              ? widget.rule?.rateLimit
              : _interval == 0
              ? null
              : 1,
          timeWindow: _interval == -1
              ? widget.rule?.timeWindow
              : _interval == 0
              ? null
              : _interval,
        ),
        _targets.toList(),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    final chats = widget.availableChats
        .where(
          (c) =>
              (c.enabled && c.isAccessible && c.isPushTarget) ||
              _targets.contains(c.id),
        )
        .toList();
    final platforms = <String, String>{
      '': '所有平台',
      'bilibili': '哔哩哔哩',
      'zhihu': '知乎',
      'xiaohongshu': '小红书',
      'weibo': '微博',
      'twitter': 'X',
      'telegram': 'Telegram',
      'universal': '网页',
    };
    if (!platforms.containsKey(_platform)) platforms[_platform] = _platform;
    return BrowserLeaveGuard(
      enabled: !_exitAllowed && (_saving || _dirty),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
        child: Form(
          key: _form,
          canPop: _exitAllowed || (!_saving && !_dirty),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _close();
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: AbsorbPointer(
              absorbing: _saving,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: '规则名称'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入规则名称' : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用规则'),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                  ),
                  _heading('内容筛选'),
                  DropdownButtonFormField<String>(
                    initialValue: _platform,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '来源平台'),
                    items: [
                      for (final e in platforms.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _platform = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _include,
                    decoration: const InputDecoration(
                      labelText: '包含标签',
                      helperText: '多个标签用逗号分隔；留空则不限标签',
                    ),
                  ),
                  if (_include.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _matchMode,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'any', child: Text('含任意一个标签')),
                        DropdownMenuItem(value: 'all', child: Text('同时包含所有标签')),
                      ],
                      onChanged: (v) => setState(() => _matchMode = v!),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _exclude,
                    decoration: const InputDecoration(labelText: '排除标签（可选）'),
                  ),
                  _heading('发送目标'),
                  for (final chat in chats)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(chat.displayName),
                      subtitle: Text(
                        '${chat.chatTypeLabel}${!chat.enabled || !chat.isAccessible || !chat.isPushTarget ? ' · 当前不可用' : ''}',
                      ),
                      value: _targets.contains(chat.id),
                      onChanged: (v) => setState(() {
                        v == true
                            ? _targets.add(chat.id)
                            : _targets.remove(chat.id);
                      }),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: widget.onManageTargets,
                      icon: const Icon(Icons.settings_outlined),
                      label: Text(chats.isEmpty ? '添加推送目标' : '管理推送目标'),
                    ),
                  ),
                  _heading('发送方式'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('发送前由我确认'),
                    value: _approval,
                    onChanged: (v) => setState(() => _approval = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _interval,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '发送频率'),
                    items: [
                      if (_interval == -1)
                        DropdownMenuItem(
                          value: -1,
                          child: Text(
                            '现有设置：每 ${widget.rule!.timeWindow} 秒最多 ${widget.rule!.rateLimit} 条',
                          ),
                        ),
                      const DropdownMenuItem(value: 0, child: Text('不额外限制')),
                      const DropdownMenuItem(
                        value: 300,
                        child: Text('每 5 分钟最多 1 条'),
                      ),
                      const DropdownMenuItem(
                        value: 900,
                        child: Text('每 15 分钟最多 1 条'),
                      ),
                      const DropdownMenuItem(
                        value: 3600,
                        child: Text('每小时最多 1 条'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _interval = v!),
                  ),
                  const SizedBox(height: 16),
                  RenderConfigEditor(
                    config: _render,
                    onChanged: (v) => setState(() => _render = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _nsfw,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '敏感内容'),
                    items: const [
                      DropdownMenuItem(value: 'block', child: Text('不发送')),
                      DropdownMenuItem(value: 'allow', child: Text('允许发送')),
                      DropdownMenuItem(
                        value: 'separate_channel',
                        child: Text('发往目标配置的敏感内容频道'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _nsfw = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: '备注（可选）'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : _close,
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '正在保存…' : '保存规则'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
