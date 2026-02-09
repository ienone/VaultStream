import 'package:flutter/material.dart';
import '../models/distribution_rule.dart';
import 'render_config_editor.dart';
import 'target_editor_dialog.dart';

class DistributionRuleDialog extends StatefulWidget {
  final DistributionRule? rule;
  final Function(DistributionRuleCreate) onCreate;
  final Function(int, DistributionRuleUpdate)? onUpdate;

  const DistributionRuleDialog({
    super.key,
    this.rule,
    required this.onCreate,
    this.onUpdate,
  });

  @override
  State<DistributionRuleDialog> createState() => _DistributionRuleDialogState();
}

class _DistributionRuleDialogState extends State<DistributionRuleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priorityController;
  late final TextEditingController _rateLimitController;
  late final TextEditingController _timeWindowController;

  late String _nsfwPolicy;
  late bool _approvalRequired;
  late bool _enabled;
  
  late List<String> _includeTags;
  late List<String> _excludeTags;
  late String _tagsMatchMode;
  late List<Map<String, dynamic>> _targets;
  late Map<String, dynamic> _renderConfig;

  bool get isEditing => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _descriptionController =
        TextEditingController(text: rule?.description ?? '');
    _priorityController =
        TextEditingController(text: (rule?.priority ?? 0).toString());
    _rateLimitController =
        TextEditingController(text: rule?.rateLimit?.toString() ?? '');
    _timeWindowController =
        TextEditingController(text: rule?.timeWindow?.toString() ?? '');
    _nsfwPolicy = rule?.nsfwPolicy ?? 'block';
    _approvalRequired = rule?.approvalRequired ?? false;
    _enabled = rule?.enabled ?? true;
    
    final conditions = rule?.matchConditions ?? {};
    _includeTags = List.from(conditions['tags'] ?? []);
    _excludeTags = List.from(conditions['tags_exclude'] ?? []);
    _tagsMatchMode = conditions['tags_match_mode'] ?? 'any';
    _targets = List.from(rule?.targets ?? []);
    _renderConfig = Map<String, dynamic>.from(rule?.renderConfig ?? {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priorityController.dispose();
    _rateLimitController.dispose();
    _timeWindowController.dispose();
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
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
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
                  child: Icon(Icons.settings_suggest_rounded, color: colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Text(
                  isEditing ? '编辑分发规则' : '创建分发规则',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Flexible(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 6, bottom: 6), 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTextField(
                        controller: _nameController,
                        label: '规则名称',
                        hint: '为规则起一个直观的名字',
                        icon: Icons.label_important_rounded,
                        validator: (v) => v == null || v.isEmpty ? '请输入规则名称' : null,
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: _descriptionController,
                        label: '规则描述',
                        hint: '可选：描述该规则的用途',
                        icon: Icons.description_rounded,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 32),
                      _buildSubHeader('分发策略'),
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
                              controller: _rateLimitController,
                              label: '频率限制',
                              hint: '最大推送数',
                              icon: Icons.speed_rounded,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: _timeWindowController,
                        label: '时间窗口 (秒)',
                        hint: '3600',
                        icon: Icons.timer_rounded,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 24),
                      _buildSwitchTile(
                        title: '人工审批',
                        subtitle: '开启后，符合规则的内容需在“待审批”中手动确认',
                        icon: Icons.rate_review_rounded,
                        value: _approvalRequired,
                        onChanged: (v) => setState(() => _approvalRequired = v),
                      ),
                      _buildSwitchTile(
                        title: '启用该规则',
                        subtitle: '控制该规则是否立即生效',
                        icon: Icons.power_settings_new_rounded,
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                      const SizedBox(height: 32),
                      _buildSubHeader('标签匹配'),
                      const SizedBox(height: 16),
                      _TagInput(
                        label: '包含标签',
                        tags: _includeTags,
                        onChanged: (tags) => setState(() => _includeTags = tags),
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
                            DropdownMenuEntry(value: 'any', label: '包含任一 (Any)'),
                            DropdownMenuEntry(value: 'all', label: '包含所有 (All)'),
                          ],
                          onChanged: (v) => setState(() => _tagsMatchMode = v!),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _TagInput(
                        label: '排除标签',
                        tags: _excludeTags,
                        onChanged: (tags) => setState(() => _excludeTags = tags),
                        placeholder: '输入要过滤的标签',
                        chipColor: colorScheme.error,
                      ),
                      const SizedBox(height: 32),
                      _buildRenderConfigSection(),
                      const SizedBox(height: 32),
                      _buildTargetsSection(context),
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
                  child: Text(isEditing ? '保存修改' : '创建规则'),
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
              ButtonSegment(value: 'block', label: Text('阻止'), icon: Icon(Icons.block_rounded, size: 18)),
              ButtonSegment(value: 'allow', label: Text('允许'), icon: Icon(Icons.check_circle_outline_rounded, size: 18)),
              ButtonSegment(value: 'separate_channel', label: Text('分离'), icon: Icon(Icons.call_split_rounded, size: 18)),
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
      margin: const EdgeInsets.only(top: 12),
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

  Widget _buildRenderConfigSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.tertiary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.palette_rounded, size: 20, color: colorScheme.tertiary),
        ),
        title: const Text('渲染配置', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(
          _renderConfig.isEmpty ? '使用默认渲染配置' : '已自定义',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: RenderConfigEditor(
              config: _renderConfig,
              onChanged: (cfg) => setState(() => _renderConfig = cfg),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetsSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSubHeader('分发目标'),
            IconButton.filledTonal(
              onPressed: _showAddTargetDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: '添加目标',
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_targets.isEmpty)
          _buildEmptyTargets(colorScheme)
        else
          ..._targets.asMap().entries.map((entry) => _buildTargetCard(entry.key, entry.value, colorScheme)),
      ],
    );
  }

  Widget _buildEmptyTargets(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: colorScheme.error),
          const SizedBox(width: 16),
          const Expanded(
            child: Text('尚未配置分发目标，该规则目前不会产生任何推送动作。', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard(int index, Map<String, dynamic> target, ColorScheme colorScheme) {
    final platform = target['platform'] ?? 'telegram';
    final hasOverride = target['render_config'] != null && (target['render_config'] as Map).isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => _showEditTargetDialog(index, target),
        leading: Icon(platform == 'telegram' ? Icons.telegram : Icons.chat_rounded, color: Colors.blue),
        title: Row(
          children: [
            Flexible(child: Text(target['target_id'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
            if (hasOverride) ...[
              const SizedBox(width: 6),
              Icon(Icons.palette_rounded, size: 14, color: colorScheme.tertiary),
            ],
          ],
        ),
        subtitle: Text(platform.toUpperCase(), style: TextStyle(fontSize: 11, color: colorScheme.outline)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: target['enabled'] ?? true,
              onChanged: (v) => setState(() => _targets[index] = {...target, 'enabled': v}),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              onPressed: () => setState(() => _targets.removeAt(index)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTargetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => TargetEditorDialog(
        onSave: (target) => setState(() => _targets.add(target)),
      ),
    );
  }

  void _showEditTargetDialog(int index, Map<String, dynamic> target) {
    showDialog(
      context: context,
      builder: (ctx) => TargetEditorDialog(
        target: target,
        onSave: (updated) => setState(() => _targets[index] = updated),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final matchConditions = {
      if (_includeTags.isNotEmpty) 'tags': _includeTags,
      if (_excludeTags.isNotEmpty) 'tags_exclude': _excludeTags,
      'tags_match_mode': _tagsMatchMode,
    };
    final create = DistributionRuleCreate(
      name: _nameController.text,
      description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
      matchConditions: matchConditions,
      targets: _targets,
      priority: int.tryParse(_priorityController.text) ?? 0,
      nsfwPolicy: _nsfwPolicy,
      approvalRequired: _approvalRequired,
      enabled: _enabled,
      rateLimit: int.tryParse(_rateLimitController.text),
      timeWindow: int.tryParse(_timeWindowController.text),
      renderConfig: _renderConfig.isEmpty ? null : _renderConfig,
    );
    if (isEditing) {
      widget.onUpdate?.call(widget.rule!.id, DistributionRuleUpdate(
        name: create.name, description: create.description, matchConditions: create.matchConditions,
        targets: create.targets, priority: create.priority, nsfwPolicy: create.nsfwPolicy,
        approvalRequired: create.approvalRequired, enabled: create.enabled, rateLimit: create.rateLimit, timeWindow: create.timeWindow,
        renderConfig: create.renderConfig,
      ));
    } else {
      widget.onCreate(create);
    }
    Navigator.of(context).pop();
  }
}

class _TagInput extends StatefulWidget {
  final String label;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String placeholder;
  final Color chipColor;

  const _TagInput({
    required this.label,
    required this.tags,
    required this.onChanged,
    required this.placeholder,
    required this.chipColor,
  });

  @override
  State<_TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<_TagInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addTag() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && !widget.tags.contains(text)) {
      widget.onChanged([...widget.tags, text]);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.placeholder,
            prefixIcon: const Icon(Icons.tag_rounded, size: 20),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            suffixIcon: IconButton(onPressed: _addTag, icon: const Icon(Icons.add_circle_outline_rounded)),
          ),
          onFieldSubmitted: (_) => _addTag(),
        ),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags.map((tag) => InputChip(
              label: Text(tag),
              labelStyle: TextStyle(
                color: widget.chipColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              backgroundColor: widget.chipColor.withValues(alpha: 0.08),
              side: BorderSide(color: widget.chipColor.withValues(alpha: 0.15)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onDeleted: () => widget.onChanged(List<String>.from(widget.tags)..remove(tag)),
              deleteIcon: const Icon(Icons.close_rounded, size: 16),
              deleteIconColor: widget.chipColor,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
        ],
      ],
    );
  }
}