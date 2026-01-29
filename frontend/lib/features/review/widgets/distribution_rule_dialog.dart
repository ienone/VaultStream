import 'package:flutter/material.dart';
import '../models/distribution_rule.dart';

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
  
  // Tag filtering state
  late List<String> _includeTags;
  late List<String> _excludeTags;
  late String _tagsMatchMode;
  
  // Targets state
  late List<Map<String, dynamic>> _targets;

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
    
    // Initialize tag filters
    final conditions = rule?.matchConditions ?? {};
    _includeTags = List.from(conditions['tags'] ?? []);
    _excludeTags = List.from(conditions['tags_exclude'] ?? []);
    _tagsMatchMode = conditions['tags_match_mode'] ?? 'any';
    
    // Initialize targets
    _targets = List.from(rule?.targets ?? []);
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
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(isEditing ? '编辑分发规则' : '创建分发规则'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '规则名称 *',
                    hintText: '输入规则名称',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? '请输入规则名称' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '描述',
                    hintText: '规则描述（可选）',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
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
                          DropdownMenuItem(value: 'block', child: Text('阻止')),
                          DropdownMenuItem(value: 'allow', child: Text('允许')),
                          DropdownMenuItem(
                            value: 'separate_channel',
                            child: Text('分离频道'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _nsfwPolicy = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _rateLimitController,
                        decoration: const InputDecoration(
                          labelText: '速率限制',
                          hintText: '每时间窗口最大推送数',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _timeWindowController,
                        decoration: const InputDecoration(
                          labelText: '时间窗口 (秒)',
                          hintText: '3600',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('需要审批'),
                  subtitle: const Text('推送前需要人工审批'),
                  value: _approvalRequired,
                  onChanged: (v) => setState(() => _approvalRequired = v),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('启用规则'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                _buildTargetsSection(context),
                const SizedBox(height: 16),
                Text(
                  '标签筛选',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _TagInput(
                  label: '包含标签',
                  tags: _includeTags,
                  onChanged: (tags) => setState(() => _includeTags = tags),
                  placeholder: '输入标签后回车添加',
                  chipColor: Colors.blue,
                ),
                if (_includeTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _tagsMatchMode,
                    decoration: const InputDecoration(
                      labelText: '标签匹配模式',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'any', child: Text('包含任一 (Any)')),
                      DropdownMenuItem(value: 'all', child: Text('包含所有 (All)')),
                    ],
                    onChanged: (v) => setState(() => _tagsMatchMode = v!),
                  ),
                ],
                const SizedBox(height: 12),
                _TagInput(
                  label: '排除标签',
                  tags: _excludeTags,
                  onChanged: (tags) => setState(() => _excludeTags = tags),
                  placeholder: '输入标签后回车排除',
                  chipColor: Colors.red,
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
          child: Text(isEditing ? '保存' : '创建'),
        ),
      ],
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
            Text(
              '分发目标',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              onPressed: _showAddTargetDialog,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '添加目标',
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_targets.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 16, color: colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  '未配置分发目标，规则将不会生效',
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                ),
              ],
            ),
          )
        else
          ..._targets.asMap().entries.map((entry) {
            final index = entry.key;
            final target = entry.value;
            final platform = target['platform'] ?? 'telegram';
            final targetId = target['target_id'] ?? '';
            final enabled = target['enabled'] ?? true;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(
                  platform == 'telegram' ? Icons.telegram : Icons.public,
                  color: platform == 'telegram' ? Colors.blue : null,
                ),
                title: Text(targetId),
                subtitle: Text(platform),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: enabled,
                      onChanged: (v) {
                        setState(() {
                          _targets[index] = {...target, 'enabled': v};
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        setState(() {
                          _targets.removeAt(index);
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _showAddTargetDialog() {
    String platform = 'telegram';
    final targetIdController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加分发目标'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: platform,
              decoration: const InputDecoration(labelText: '平台'),
              items: const [
                DropdownMenuItem(value: 'telegram', child: Text('Telegram')),
                // Add other platforms if needed
              ],
              onChanged: (v) => platform = v!,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: targetIdController,
              decoration: const InputDecoration(
                labelText: '目标 ID',
                hintText: '例如: @channel_name',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (targetIdController.text.isNotEmpty) {
                setState(() {
                  _targets.add({
                    'platform': platform,
                    'target_id': targetIdController.text.trim(),
                    'enabled': true,
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final priority = int.tryParse(_priorityController.text) ?? 0;
    final rateLimit = int.tryParse(_rateLimitController.text);
    final timeWindow = int.tryParse(_timeWindowController.text);

    final matchConditions = {
      if (_includeTags.isNotEmpty) 'tags': _includeTags,
      if (_excludeTags.isNotEmpty) 'tags_exclude': _excludeTags,
      'tags_match_mode': _tagsMatchMode,
    };

    if (isEditing) {
      widget.onUpdate?.call(
        widget.rule!.id,
        DistributionRuleUpdate(
          name: _nameController.text,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          matchConditions: matchConditions,
          targets: _targets,
          priority: priority,
          nsfwPolicy: _nsfwPolicy,
          approvalRequired: _approvalRequired,
          enabled: _enabled,
          rateLimit: rateLimit,
          timeWindow: timeWindow,
        ),
      );
    } else {
      widget.onCreate(
        DistributionRuleCreate(
          name: _nameController.text,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          matchConditions: matchConditions,
          targets: _targets,
          priority: priority,
          nsfwPolicy: _nsfwPolicy,
          approvalRequired: _approvalRequired,
          enabled: _enabled,
          rateLimit: rateLimit,
          timeWindow: timeWindow,
        ),
      );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.placeholder,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: _addTag,
              icon: const Icon(Icons.add),
            ),
          ),
          onFieldSubmitted: (_) => _addTag(),
        ),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.tags.map((tag) {
              return Chip(
                label: Text(tag),
                labelStyle: TextStyle(
                  color: widget.chipColor,
                  fontSize: 12,
                ),
                backgroundColor: widget.chipColor.withValues(alpha: 0.1),
                side: BorderSide(color: widget.chipColor.withValues(alpha: 0.3)),
                onDeleted: () {
                  final newTags = List<String>.from(widget.tags)..remove(tag);
                  widget.onChanged(newTags);
                },
                deleteIconColor: widget.chipColor,
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}

