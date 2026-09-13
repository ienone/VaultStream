import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/toast.dart';
import '../../../theme/design_tokens.dart';
import '../models/render_config.dart';
import '../models/render_config_preset.dart';
import '../providers/render_config_presets_provider.dart';

class RenderConfigEditor extends ConsumerStatefulWidget {
  const RenderConfigEditor({
    super.key,
    required this.config,
    required this.onChanged,
    this.showPresetSelector = true,
  });

  final RenderConfig config;
  final ValueChanged<RenderConfig> onChanged;
  final bool showPresetSelector;

  @override
  ConsumerState<RenderConfigEditor> createState() => _RenderConfigEditorState();
}

class _RenderConfigEditorState extends ConsumerState<RenderConfigEditor> {
  late final TextEditingController _headerController;
  late final TextEditingController _footerController;

  Map<String, dynamic> get _structure {
    return widget.config.structure;
  }

  @override
  void initState() {
    super.initState();
    final s = _structure;
    _headerController = TextEditingController(text: s['header_text'] ?? '');
    _footerController = TextEditingController(text: s['footer_text'] ?? '');
  }

  @override
  void dispose() {
    _headerController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  void _updateField(String key, dynamic value) {
    final s = _structure;
    s[key] = value;
    _emitChange(s);
  }

  void _emitChange(Map<String, dynamic> structure) {
    widget.onChanged(widget.config.withStructure(structure));
  }

  bool _getBool(String key, [bool fallback = false]) =>
      (_structure[key] as bool?) ?? fallback;

  String _getString(String key, [String fallback = '']) =>
      (_structure[key] as String?) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final presetsAsync = ref.watch(renderConfigPresetsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showPresetSelector)
          presetsAsync.when(
            data: (presets) => presets.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _buildPresetSelector(presets),
                  ),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
        _sectionLabel('显示控制'),
        const SizedBox(height: 8),
        _switchTile(
          title: '显示平台 ID',
          value: _getBool('show_platform_id', true),
          onChanged: (v) => _updateField('show_platform_id', v),
        ),
        _switchTile(
          title: '显示标题',
          value: _getBool('show_title', true),
          onChanged: (v) => _updateField('show_title', v),
        ),
        _switchTile(
          title: '显示标签',
          value: _getBool('show_tags'),
          onChanged: (v) => _updateField('show_tags', v),
        ),
        const SizedBox(height: 24),
        _sectionLabel('内容模式'),
        const SizedBox(height: 12),
        _modeSelector(
          label: '作者显示',
          value: _getString('author_mode', 'full'),
          options: const {'none': '隐藏', 'name': '昵称', 'full': '完整'},
          onChanged: (v) => _updateField('author_mode', v),
        ),
        const SizedBox(height: 16),
        _modeSelector(
          label: '正文模式',
          value: _getString('content_mode', 'summary'),
          options: const {'hidden': '隐藏', 'summary': '摘要', 'full': '完整'},
          onChanged: (v) => _updateField('content_mode', v),
        ),
        const SizedBox(height: 16),
        _modeSelector(
          label: '媒体模式',
          value: _getString('media_mode', 'auto'),
          options: const {'none': '不含', 'auto': '自动', 'all': '全部'},
          onChanged: (v) => _updateField('media_mode', v),
        ),
        const SizedBox(height: 16),
        _modeSelector(
          label: '链接模式',
          value: _getString('link_mode', 'clean'),
          options: const {'none': '不含', 'clean': '精简', 'original': '原始'},
          onChanged: (v) => _updateField('link_mode', v),
        ),
        const SizedBox(height: 24),
        _sectionLabel('模板文本'),
        const SizedBox(height: 12),
        _buildTextInput(
          controller: _headerController,
          label: '头部文本',
          hint: '支持变量: {{date}}, {{title}}',
          onChanged: (v) => _updateField('header_text', v),
        ),
        const SizedBox(height: 16),
        _buildTextInput(
          controller: _footerController,
          label: '尾部文本',
          hint: '支持变量: {{date}}, {{title}}',
          onChanged: (v) => _updateField('footer_text', v),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _switchTile({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _modeSelector({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    final labelWidget = Text(
      label,
      style: Theme.of(context).textTheme.bodyLarge,
    );
    final choices = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final option in options.entries)
          ChoiceChip(
            label: Text(option.value),
            selected: value == option.key,
            showCheckmark: true,
            onSelected: (_) => onChanged(option.key),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth >= 520 * textScale) {
          return Row(
            children: [
              SizedBox(width: 144 * textScale, child: labelWidget),
              Expanded(child: choices),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [labelWidget, const SizedBox(height: 8), choices],
        );
      },
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      minLines: 2,
      maxLines: 4,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        hintText: hint,
        contentPadding: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }

  Widget _buildPresetSelector(List<RenderConfigPreset> presets) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('预设模板'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            return ActionChip(
              avatar: Icon(
                _getPresetIcon(preset.id),
                size: 18,
                color: colorScheme.primary,
              ),
              label: Text(preset.name),
              tooltip: preset.description,
              onPressed: () => _applyPreset(preset),
            );
          }).toList(),
        ),
      ],
    );
  }

  IconData _getPresetIcon(String id) {
    switch (id) {
      case 'minimal':
        return Icons.minimize_rounded;
      case 'standard':
        return Icons.view_agenda_rounded;
      case 'detailed':
        return Icons.list_alt_rounded;
      case 'media_only':
        return Icons.photo_library_rounded;
      default:
        return Icons.bookmarks_rounded;
    }
  }

  void _applyPreset(RenderConfigPreset preset) {
    // Apply preset config
    final presetConfig = preset.config.structure;

    // Update text controllers
    _headerController.text = presetConfig['header_text'] ?? '';
    _footerController.text = presetConfig['footer_text'] ?? '';

    // Emit change
    _emitChange(presetConfig);

    // Show feedback
    Toast.show(context, '已应用预设: ${preset.name}');
  }
}
