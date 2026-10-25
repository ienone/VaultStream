import '../../../core/widgets/app_multi_select.dart';
import '../../../core/widgets/app_filter_menu.dart';
import '../../../core/layout/app_page_body.dart';

import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/app_choice_segments.dart';

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
  final _nameField = GlobalKey();
  final _targetField = GlobalKey();
  final _nameFocus = FocusNode();
  bool _missingTarget = false;

  void _reveal(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || key.currentContext == null) return;
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: .15,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.standard,
        curve: AppMotion.standardCurve,
      );
    });
  }

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
    _nameFocus.dispose();
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
    if (!_form.currentState!.validate()) {
      _nameFocus.requestFocus();
      _reveal(_nameField);
      return;
    }
    if (_targets.isEmpty) {
      setState(() => _missingTarget = true);
      _reveal(_targetField);
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
      child: AppPageBody(
        maxWidth: AppPane.readableMaxWidth,
        child: Form(
          key: _form,
          canPop: _exitAllowed || (!_saving && !_dirty),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _close();
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            child: AbsorbPointer(
              absorbing: _saving,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: _nameField,
                    focusNode: _nameFocus,
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
                  Semantics(
                    label: '来源平台',
                    child: AppFilterMenu(
                      label: '来源平台',
                      value: _platform,
                      options: platforms,
                      onSelected: (v) => setState(() => _platform = v),
                    ),
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
                    AppChoiceSegments<String>(
                      options: const {'any': '任意标签', 'all': '全部标签'},
                      selected: {_matchMode},
                      onChanged: (values) =>
                          setState(() => _matchMode = values.first),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _exclude,
                    decoration: const InputDecoration(labelText: '排除标签（可选）'),
                  ),
                  KeyedSubtree(key: _targetField, child: _heading('发送目标')),
                  if (_missingTarget)
                    Text(
                      '请选择至少一个推送目标',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  AppMultiSelect(
                    label: '发送到',
                    hint: '选择目标',
                    options: {
                      for (final chat in chats)
                        '${chat.id}':
                            '${chat.displayName}${!chat.enabled || !chat.isAccessible || !chat.isPushTarget ? '（当前不可用）' : ''}',
                    },
                    selected: _targets.map((id) => '$id').toSet(),
                    onChanged: (values) => setState(() {
                      _missingTarget = false;
                      _targets = values.map(int.parse).toSet();
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
                  Semantics(
                    label: '发送频率',
                    child: AppFilterMenu(
                      label: '发送频率',
                      value: '$_interval',
                      options: {
                        if (_interval == -1)
                          '-1':
                              '现有设置：每 ${widget.rule!.timeWindow} 秒最多 ${widget.rule!.rateLimit} 条',
                        '0': '不额外限制',
                        '300': '每 5 分钟最多 1 条',
                        '900': '每 15 分钟最多 1 条',
                        '3600': '每小时最多 1 条',
                      },
                      onSelected: (v) =>
                          setState(() => _interval = int.parse(v)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  RenderConfigEditor(
                    config: _render,
                    onChanged: (v) => setState(() => _render = v),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: '敏感内容',
                    child: AppFilterMenu(
                      label: '敏感内容',
                      value: _nsfw,
                      options: const {
                        'block': '不发送',
                        'allow': '允许发送',
                        'separate_channel': '发往目标配置的敏感内容频道',
                      },
                      onSelected: (v) => setState(() => _nsfw = v),
                    ),
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
