import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/widgets/discard_changes_dialog.dart';

import '../../../theme/design_tokens.dart';
import '../../../core/widgets/browser_leave_guard.dart';
import '../models/distribution_rule.dart';
import '../models/bot_chat.dart';
import '../models/render_config.dart';
import 'render_config_editor.dart';

class DistributionRuleEditor extends StatefulWidget {
  final DistributionRule? rule;
  final Future<void> Function(DistributionRuleCreate, List<int>, String, int?)
  onCreate;
  final Future<void> Function(
    int,
    DistributionRuleUpdate,
    List<int>,
    String,
    int?,
  )?
  onUpdate;
  final VoidCallback onCancel;
  final VoidCallback? onManageTargets;
  final List<BotChat> availableChats;
  final List<int> initialSelectedChatIds;

  const DistributionRuleEditor({
    super.key,
    this.rule,
    required this.onCreate,
    this.onUpdate,
    required this.onCancel,
    this.onManageTargets,
    this.availableChats = const [],
    this.initialSelectedChatIds = const [],
  });

  @override
  State<DistributionRuleEditor> createState() => DistributionRuleEditorState();
}

class DistributionRuleEditorState extends State<DistributionRuleEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priorityController;
  late final TextEditingController _rateLimitController;
  late final TextEditingController _timeWindowController;
  late final TextEditingController _backfillRecentDaysController;
  final _includeTagController = TextEditingController();
  final _excludeTagController = TextEditingController();

  late String _nsfwPolicy;
  late bool _approvalRequired;
  late bool _enabled;

  late List<String> _includeTags;
  late List<String> _excludeTags;
  late String _tagsMatchMode;
  late RenderConfig _renderConfig;
  late Set<int> _selectedTargetChatIds;
  late String _backfillMode;
  bool _saving = false;
  bool _confirmingExit = false;
  bool _exitAllowed = false;
  late final String _initialDraft;

  List<TextEditingController> get _controllers => [
    _nameController,
    _descriptionController,
    _priorityController,
    _rateLimitController,
    _timeWindowController,
    _backfillRecentDaysController,
    _includeTagController,
    _excludeTagController,
  ];

  String _draftSnapshot() => jsonEncode({
    'text': _controllers.map((controller) => controller.text).toList(),
    'nsfw': _nsfwPolicy,
    'approval': _approvalRequired,
    'enabled': _enabled,
    'includeTags': _includeTags,
    'excludeTags': _excludeTags,
    'tagsMatchMode': _tagsMatchMode,
    'renderConfig': _renderConfig,
    'targets': _selectedTargetChatIds.toList()..sort(),
    'backfill': _backfillMode,
  });

  bool get _hasChanges => _draftSnapshot() != _initialDraft;

  void _draftChanged() => setState(() {});

  Future<void> _requestClose() async {
    if (await confirmExit() && mounted) widget.onCancel();
  }

  void allowExitAfterSave() => setState(() => _exitAllowed = true);

  Future<bool> confirmExit() async {
    if (_exitAllowed) return true;
    if (_saving || _confirmingExit) return false;
    if (!_hasChanges) return true;
    _confirmingExit = true;
    final discard = await showDiscardChangesDialog(
      context,
      title: '放弃未保存的修改？',
      message: '退出后，本次修改不会保存。',
    );
    _confirmingExit = false;
    if (discard == true && mounted) {
      setState(() => _exitAllowed = true);
      return true;
    }
    return false;
  }

  bool get isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _descriptionController = TextEditingController(
      text: rule?.description ?? '',
    );
    _priorityController = TextEditingController(
      text: (rule?.priority ?? 0).toString(),
    );
    _rateLimitController = TextEditingController(
      text: rule?.rateLimit?.toString() ?? '',
    );
    _timeWindowController = TextEditingController(
      text: rule?.timeWindow?.toString() ?? '',
    );
    _backfillRecentDaysController = TextEditingController(text: '30');
    _nsfwPolicy = rule?.nsfwPolicy ?? 'block';
    _approvalRequired = rule?.approvalRequired ?? false;
    _enabled = rule?.enabled ?? true;

    final conditions = rule?.matchConditions ?? {};
    _includeTags = List.from(conditions['tags'] ?? []);
    _excludeTags = List.from(conditions['tags_exclude'] ?? []);
    _tagsMatchMode = conditions['tags_match_mode'] ?? 'any';
    _renderConfig = rule?.renderConfig ?? {};
    _selectedTargetChatIds = Set<int>.from(widget.initialSelectedChatIds);
    _backfillMode = 'new_only';
    _initialDraft = _draftSnapshot();
    for (final controller in _controllers) {
      controller.addListener(_draftChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 640;

    return BrowserLeaveGuard(
      enabled: !_exitAllowed && (_saving || _hasChanges),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortViewport = constraints.maxHeight < 300;
          return Container(
            constraints: BoxConstraints(
              maxWidth: compact ? double.infinity : AppPane.readableMaxWidth,
              maxHeight: double.infinity,
            ),
            padding: shortViewport
                ? EdgeInsets.symmetric(horizontal: compact ? 20 : AppSpacing.xl)
                : compact
                ? const EdgeInsets.fromLTRB(20, 20, 20, 16)
                : const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Form(
                    key: _formKey,
                    canPop: _exitAllowed || (!_saving && !_hasChanges),
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) _requestClose();
                    },
                    child: AbsorbPointer(
                      absorbing: _saving,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 6, bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTextField(
                              controller: _nameController,
                              label: '规则名称',
                              hint: '为规则起一个直观的名字',
                              validator: (v) =>
                                  v == null || v.isEmpty ? '请输入规则名称' : null,
                            ),
                            const SizedBox(height: 24),
                            _buildSubHeader('哪些内容'),
                            const SizedBox(height: 16),
                            _TagInput(
                              controller: _includeTagController,
                              label: '包含标签',
                              tags: _includeTags,
                              onChanged: (tags) =>
                                  setState(() => _includeTags = tags),
                              placeholder: '输入标签后回车',
                              chipColor: colorScheme.primary,
                            ),
                            if (_includeTags.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildExpressiveDropdown<String>(
                                label: '匹配模式',
                                value: _tagsMatchMode,
                                icon: Icons.api_rounded,
                                entries: const [
                                  DropdownMenuEntry(
                                    value: 'any',
                                    label: '包含任一',
                                  ),
                                  DropdownMenuEntry(
                                    value: 'all',
                                    label: '包含全部',
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _tagsMatchMode = v!),
                              ),
                            ],
                            const SizedBox(height: 16),
                            _TagInput(
                              controller: _excludeTagController,
                              label: '排除标签',
                              tags: _excludeTags,
                              onChanged: (tags) =>
                                  setState(() => _excludeTags = tags),
                              placeholder: '输入要过滤的标签',
                              chipColor: colorScheme.error,
                            ),
                            const SizedBox(height: 32),
                            _buildNsfwSelector(),
                            const SizedBox(height: 16),
                            _buildSubHeader('发到哪里'),
                            const SizedBox(height: 12),
                            _buildTargetSelector(),
                            const SizedBox(height: 24),
                            _buildSubHeader('如何执行'),
                            const SizedBox(height: 8),
                            _buildSwitchTile(
                              title: '人工审批',
                              subtitle: '开启后，符合规则的内容需在“待审批”中手动确认',
                              icon: Icons.rate_review_rounded,
                              value: _approvalRequired,
                              onChanged: (v) =>
                                  setState(() => _approvalRequired = v),
                            ),
                            _buildSwitchTile(
                              title: '启用该规则',
                              subtitle: '控制该规则是否立即生效',
                              icon: Icons.power_settings_new_rounded,
                              value: _enabled,
                              onChanged: (v) => setState(() => _enabled = v),
                            ),
                            const SizedBox(height: 32),
                            ExpansionTile(
                              title: const Text('高级设置'),
                              expansionAnimationStyle: _expansionStyle,
                              shape: const Border(),
                              collapsedShape: const Border(),
                              childrenPadding: const EdgeInsets.only(
                                top: AppSpacing.md,
                              ),
                              maintainState: true,
                              tilePadding: EdgeInsets.zero,
                              children: [
                                _buildTextField(
                                  controller: _descriptionController,
                                  label: '规则描述',
                                  hint: '可选：描述该规则的用途',
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 16),
                                _buildNumericSettings(),
                                const SizedBox(height: 24),
                                _buildBackfillSelector(),
                                const SizedBox(height: 16),
                              ],
                            ),
                            _buildRenderConfigSection(),
                            if (shortViewport) ...[
                              const SizedBox(height: 24),
                              _buildActions(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!shortViewport) ...[
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActions() => OverflowBar(
    alignment: MainAxisAlignment.end,
    spacing: AppSpacing.sm,
    overflowSpacing: AppSpacing.xs,
    children: [
      TextButton(
        onPressed: _saving ? null : _requestClose,
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _submit,
        child: _saving
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(isEditing ? '保存修改' : '创建规则'),
      ),
    ],
  );

  AnimationStyle get _expansionStyle => MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: AppMotion.surfaceEnter,
          reverseDuration: AppMotion.surfaceExit,
          curve: AppMotion.standardCurve,
        );

  Widget _buildNumericSettings() => LayoutBuilder(
    builder: (context, constraints) {
      final minWidth = 200 * MediaQuery.textScalerOf(context).scale(1);
      final columns = ((constraints.maxWidth + 16) / (minWidth + 16))
          .floor()
          .clamp(1, 3);
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final field in [
            _buildTextField(
              controller: _priorityController,
              label: '优先级',
              hint: '0',
              keyboardType: TextInputType.number,
            ),
            _buildTextField(
              controller: _rateLimitController,
              label: '频率限制',
              hint: '最大推送数',
              keyboardType: TextInputType.number,
            ),
            _buildTextField(
              controller: _timeWindowController,
              label: '时间窗口 (秒)',
              hint: '3600',
              keyboardType: TextInputType.number,
            ),
          ])
            SizedBox(width: width, child: field),
        ],
      );
    },
  );

  Widget _buildTargetSelector() {
    final theme = Theme.of(context);
    final chats = widget.availableChats.where((c) => c.enabled).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    if (chats.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '还没有可用推送目标',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: widget.onManageTargets,
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加推送目标'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              '已选择 ${_selectedTargetChatIds.length} / ${chats.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selectedTargetChatIds = chats.map((c) => c.id).toSet();
                  }),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _selectedTargetChatIds.clear()),
                  child: const Text('清空'),
                ),
              ],
            ),
          ],
        ),
        for (final chat in chats)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selectedTargetChatIds.contains(chat.id),
            title: Text(chat.displayName),
            subtitle: Text(chat.chatTypeLabel),
            onChanged: (checked) {
              setState(() {
                if (checked == true) {
                  _selectedTargetChatIds.add(chat.id);
                } else {
                  _selectedTargetChatIds.remove(chat.id);
                }
              });
            },
          ),
      ],
    );
  }

  Widget _buildBackfillSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 20, color: colorScheme.outline),
            const SizedBox(width: 12),
            Text('历史内容处理', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in const {
              'new_only': '仅新内容',
              'recent_days': '最近 N 天',
              'all_history': '全部历史',
            }.entries)
              ChoiceChip(
                label: Text(option.value),
                selected: _backfillMode == option.key,
                onSelected: (_) => setState(() => _backfillMode = option.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _backfillMode == 'new_only'
              ? '新目标只接收之后入库的内容。'
              : _backfillMode == 'recent_days'
              ? '为最近一段时间内已解析并已审批的内容补建队列。'
              : '为所有已解析并已审批的历史内容补建队列。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        if (_backfillMode == 'recent_days') ...[
          const SizedBox(height: 12),
          _buildTextField(
            controller: _backfillRecentDaysController,
            label: '回填天数',
            hint: '30',
            keyboardType: TextInputType.number,
          ),
        ],
      ],
    );
  }

  Widget _buildSubHeader(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
            Text('敏感内容', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'block',
                label: Text('阻止'),
                icon: Icon(Icons.block_rounded, size: 18),
              ),
              ButtonSegment(
                value: 'allow',
                label: Text('允许'),
                icon: Icon(Icons.check_circle_outline_rounded, size: 18),
              ),
              ButtonSegment(
                value: 'separate_channel',
                label: Text('分离'),
                icon: Icon(Icons.call_split_rounded, size: 18),
              ),
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
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
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
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      itemHeight: null,
      menuMaxHeight: 400,
      borderRadius: AppShape.cardBorder,
      dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
      ),
      items: [
        for (final entry in entries)
          DropdownMenuItem<T>(
            value: entry.value,
            enabled: entry.enabled,
            child: Text(entry.label),
          ),
      ],
      onTap: () => FocusScope.of(context).unfocus(),
      onChanged: onChanged,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildRenderConfigSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('推送格式', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      RenderConfigEditor(
        config: _renderConfig,
        onChanged: (cfg) => setState(() => _renderConfig = cfg),
      ),
    ],
  );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final matchConditions = {
      if (_includeTags.isNotEmpty) 'tags': _includeTags,
      if (_excludeTags.isNotEmpty) 'tags_exclude': _excludeTags,
      'tags_match_mode': _tagsMatchMode,
    };
    final create = DistributionRuleCreate(
      name: _nameController.text,
      description: _descriptionController.text.isEmpty
          ? null
          : _descriptionController.text,
      matchConditions: matchConditions,
      priority: int.tryParse(_priorityController.text) ?? 0,
      nsfwPolicy: _nsfwPolicy,
      approvalRequired: _approvalRequired,
      enabled: _enabled,
      rateLimit: int.tryParse(_rateLimitController.text),
      timeWindow: int.tryParse(_timeWindowController.text),
      renderConfig: _renderConfig.isEmpty ? null : _renderConfig,
    );
    final recentDays = _backfillMode == 'recent_days'
        ? (int.tryParse(_backfillRecentDaysController.text) ?? 30)
        : null;
    setState(() => _saving = true);
    try {
      if (isEditing) {
        await widget.onUpdate?.call(
          widget.rule!.id,
          DistributionRuleUpdate(
            name: create.name,
            description: create.description,
            matchConditions: create.matchConditions,
            priority: create.priority,
            nsfwPolicy: create.nsfwPolicy,
            approvalRequired: create.approvalRequired,
            enabled: create.enabled,
            rateLimit: create.rateLimit,
            timeWindow: create.timeWindow,
            renderConfig: create.renderConfig,
          ),
          _selectedTargetChatIds.toList()..sort(),
          _backfillMode,
          recentDays,
        );
      } else {
        await widget.onCreate(
          create,
          _selectedTargetChatIds.toList()..sort(),
          _backfillMode,
          recentDays,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _TagInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String placeholder;
  final Color chipColor;

  const _TagInput({
    required this.controller,
    required this.label,
    required this.tags,
    required this.onChanged,
    required this.placeholder,
    required this.chipColor,
  });

  void _addTag() {
    final text = controller.text.trim();
    if (text.isNotEmpty && !tags.contains(text)) {
      onChanged([...tags, text]);
      controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: placeholder,
            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
            suffixIcon: IconButton(
              onPressed: _addTag,
              tooltip: '添加$label',
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ),
          onFieldSubmitted: (_) => _addTag(),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tags
                .map(
                  (tag) => Tooltip(
                    message: tag,
                    child: Chip(
                      label: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      deleteButtonTooltipMessage: '移除$label $tag',

                      labelStyle: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(
                            color: chipColor,
                            fontWeight: FontWeight.bold,
                          ),
                      backgroundColor: chipColor.withValues(alpha: 0.08),
                      side: BorderSide(
                        color: chipColor.withValues(alpha: 0.15),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppShape.cardMediaBorder,
                      ),
                      onDeleted: () =>
                          onChanged(List<String>.from(tags)..remove(tag)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      deleteIconColor: chipColor,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}
