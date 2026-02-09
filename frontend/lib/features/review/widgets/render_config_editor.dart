import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/render_config_preset.dart';
import '../providers/targets_provider.dart';

class RenderConfigEditor extends ConsumerStatefulWidget {
  const RenderConfigEditor({
    super.key,
    required this.config,
    required this.onChanged,
    this.showPresetSelector = true,
  });

  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool showPresetSelector;

  @override
  ConsumerState<RenderConfigEditor> createState() => _RenderConfigEditorState();
}

class _RenderConfigEditorState extends ConsumerState<RenderConfigEditor> {
  late final TextEditingController _headerController;
  late final TextEditingController _footerController;

  Map<String, dynamic> get _structure {
    final cfg = widget.config;
    if (cfg.containsKey('structure') && cfg['structure'] is Map) {
      return Map<String, dynamic>.from(cfg['structure'] as Map);
    }
    return Map<String, dynamic>.from(cfg);
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
    if (widget.config.containsKey('structure')) {
      widget.onChanged({'structure': structure});
    } else {
      widget.onChanged(structure);
    }
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
            data: (presets) => _buildPresetSelector(presets),
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
        if (widget.showPresetSelector) const SizedBox(height: 24),
        _sectionLabel('显示控制'),
        const SizedBox(height: 8),
        _switchTile(
          title: '显示平台 ID',
          icon: Icons.fingerprint_rounded,
          value: _getBool('show_platform_id', true),
          onChanged: (v) => _updateField('show_platform_id', v),
        ),
        _switchTile(
          title: '显示标题',
          icon: Icons.title_rounded,
          value: _getBool('show_title', true),
          onChanged: (v) => _updateField('show_title', v),
        ),
        _switchTile(
          title: '显示标签',
          icon: Icons.label_rounded,
          value: _getBool('show_tags'),
          onChanged: (v) => _updateField('show_tags', v),
        ),
        const SizedBox(height: 24),
        _sectionLabel('内容模式'),
        const SizedBox(height: 12),
        _modeSelector(
          label: '作者显示',
          icon: Icons.person_rounded,
          value: _getString('author_mode', 'full'),
          options: const {'none': '隐藏', 'name': '昵称', 'full': '完整'},
          onChanged: (v) => _updateField('author_mode', v),
        ),
        const SizedBox(height: 16),
        _modeSelector(
          label: '正文模式',
          icon: Icons.article_rounded,
          value: _getString('content_mode', 'summary'),
          options: const {'hidden': '隐藏', 'summary': '摘要', 'full': '完整'},
          onChanged: (v) => _updateField('content_mode', v),
        ),
        const SizedBox(height: 16),
        _modeSelector(
          label: '媒体模式',
          icon: Icons.image_rounded,
          value: _getString('media_mode', 'auto'),
          options: const {'none': '不含', 'auto': '自动', 'all': '全部'},
          onChanged: (v) => _updateField('media_mode', v),
        ),
        const SizedBox(height: 16),
        _modeSelector(
          label: '链接模式',
          icon: Icons.link_rounded,
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
          icon: Icons.vertical_align_top_rounded,
          onChanged: (v) => _updateField('header_text', v),
        ),
        const SizedBox(height: 16),
        _buildTextInput(
          controller: _footerController,
          label: '尾部文本',
          hint: '支持变量: {{date}}, {{title}}',
          icon: Icons.vertical_align_bottom_rounded,
          onChanged: (v) => _updateField('footer_text', v),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
    );
  }

  Widget _switchTile({
    required String title,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _modeSelector({
    required String label,
    required IconData icon,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.outline),
            const SizedBox(width: 12),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: options.entries
                .map((e) =>
                    ButtonSegment<String>(value: e.key, label: Text(e.value)))
                .toList(),
            selected: {value},
            onSelectionChanged: (sel) => onChanged(sel.first),
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

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
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

  Widget _buildPresetSelector(List<RenderConfigPreset> presets) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, 
                size: 20, color: colorScheme.primary),
            const SizedBox(width: 12),
            Text('预设模板', 
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                )),
          ],
        ),
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
              backgroundColor: colorScheme.surfaceContainerLow,
              side: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
    final presetConfig = Map<String, dynamic>.from(preset.config);
    
    // Update text controllers
    _headerController.text = presetConfig['header_text'] ?? '';
    _footerController.text = presetConfig['footer_text'] ?? '';
    
    // Emit change
    _emitChange(presetConfig);
    
    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Text('已应用预设: ${preset.name}'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

