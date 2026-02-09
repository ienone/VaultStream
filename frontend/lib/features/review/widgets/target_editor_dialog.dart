import 'package:flutter/material.dart';
import 'render_config_editor.dart';

class TargetEditorDialog extends StatefulWidget {
  const TargetEditorDialog({
    super.key,
    this.target,
    required this.onSave,
  });

  final Map<String, dynamic>? target;
  final ValueChanged<Map<String, dynamic>> onSave;

  @override
  State<TargetEditorDialog> createState() => _TargetEditorDialogState();
}

class _TargetEditorDialogState extends State<TargetEditorDialog> {
  late String _platform;
  late final TextEditingController _targetIdController;
  late final TextEditingController _summaryController;
  late bool _enabled;
  late bool _mergeForward;
  late bool _useAuthorName;
  late bool _hasRenderOverride;
  late Map<String, dynamic> _renderConfig;

  bool get isEditing => widget.target != null;

  @override
  void initState() {
    super.initState();
    final t = widget.target;
    _platform = (t?['platform'] as String?) ?? 'telegram';
    _targetIdController =
        TextEditingController(text: (t?['target_id'] as String?) ?? '');
    _summaryController =
        TextEditingController(text: (t?['summary'] as String?) ?? '');
    _enabled = (t?['enabled'] as bool?) ?? true;
    _mergeForward = (t?['merge_forward'] as bool?) ?? false;
    _useAuthorName = (t?['use_author_name'] as bool?) ?? false;
    _renderConfig =
        Map<String, dynamic>.from((t?['render_config'] as Map?) ?? {});
    _hasRenderOverride = _renderConfig.isNotEmpty;
  }

  @override
  void dispose() {
    _targetIdController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
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
                  child: Icon(Icons.track_changes_rounded,
                      color: colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Text(
                  isEditing ? '编辑分发目标' : '添加分发目标',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPlatformSelector(colorScheme),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _targetIdController,
                      label: '目标 ID',
                      hint: _platform == 'telegram'
                          ? '例如: @channel_name'
                          : '例如: group:123456',
                      icon: Icons.alternate_email_rounded,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: _summaryController,
                      label: '显示名称',
                      hint: '可选：用于合并转发时的名称',
                      icon: Icons.badge_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSwitchTile(
                      title: '启用',
                      subtitle: '是否向此目标推送',
                      icon: Icons.power_settings_new_rounded,
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                    _buildSwitchTile(
                      title: '使用作者名',
                      subtitle: '推送时显示原作者名称',
                      icon: Icons.person_rounded,
                      value: _useAuthorName,
                      onChanged: (v) => setState(() => _useAuthorName = v),
                    ),
                    if (_platform == 'qq')
                      _buildSwitchTile(
                        title: '合并转发',
                        subtitle: '使用 QQ 合并转发模式发送',
                        icon: Icons.merge_rounded,
                        value: _mergeForward,
                        onChanged: (v) => setState(() => _mergeForward = v),
                      ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ExpansionTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (_hasRenderOverride
                                    ? colorScheme.tertiary
                                    : colorScheme.outline)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.palette_rounded,
                              size: 20,
                              color: _hasRenderOverride
                                  ? colorScheme.tertiary
                                  : colorScheme.outline),
                        ),
                        title: const Text('渲染配置覆盖',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        subtitle: Text(
                          _hasRenderOverride ? '已启用自定义渲染' : '使用规则级默认配置',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Switch(
                          value: _hasRenderOverride,
                          onChanged: (v) {
                            setState(() {
                              _hasRenderOverride = v;
                              if (!v) _renderConfig = {};
                            });
                          },
                        ),
                        children: [
                          if (_hasRenderOverride)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: RenderConfigEditor(
                                config: _renderConfig,
                                onChanged: (cfg) =>
                                    setState(() => _renderConfig = cfg),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEditing ? '保存' : '添加'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hub_rounded, size: 20, color: colorScheme.outline),
            const SizedBox(width: 12),
            Text('平台', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'telegram',
                  label: Text('Telegram'),
                  icon: Icon(Icons.telegram, size: 18)),
              ButtonSegment(
                  value: 'qq',
                  label: Text('QQ'),
                  icon: Icon(Icons.chat_rounded, size: 18)),
            ],
            selected: {_platform},
            onSelectionChanged: (sel) =>
                setState(() => _platform = sel.first),
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
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (value ? colorScheme.primary : colorScheme.outline)
                .withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 20,
              color: value ? colorScheme.primary : colorScheme.outline),
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

  void _save() {
    final id = _targetIdController.text.trim();
    if (id.isEmpty) return;

    final target = <String, dynamic>{
      'platform': _platform,
      'target_id': id,
      'enabled': _enabled,
      'merge_forward': _mergeForward,
      'use_author_name': _useAuthorName,
      'summary': _summaryController.text.trim(),
    };

    if (_hasRenderOverride && _renderConfig.isNotEmpty) {
      target['render_config'] = _renderConfig;
    }

    widget.onSave(target);
    Navigator.of(context).pop();
  }
}
