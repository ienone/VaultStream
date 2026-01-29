import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/tag_provider.dart';

class FilterDialog extends ConsumerStatefulWidget {
  final List<String> initialPlatforms;
  final List<String> initialStatuses;
  final String? initialAuthor;
  final DateTimeRange? initialDateRange;
  final List<String> initialTags;
  final List<String> availableTags;

  const FilterDialog({
    super.key,
    this.initialPlatforms = const [],
    this.initialStatuses = const [],
    this.initialAuthor,
    this.initialDateRange,
    this.initialTags = const [],
    this.availableTags = const [],
  });

  @override
  ConsumerState<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends ConsumerState<FilterDialog> {
  late Set<String> _selectedPlatforms;
  late Set<String> _selectedStatuses;
  late TextEditingController _authorController;
  late TextEditingController _tagInputController;
  late DateTimeRange? _dateRange;
  late Set<String> _selectedTags;
  List<String> _tagSuggestions = [];

  final List<String> _platforms = ['bilibili', 'twitter', 'xiaohongshu', 'douyin', 'weibo', 'zhihu'];
  final List<String> _statuses = ['unprocessed', 'processing', 'pulled', 'failed', 'archived'];

  final Map<String, String> _platformLabels = {
    'bilibili': 'Bilibili', 'twitter': 'Twitter/X', 'xiaohongshu': '小红书',
    'douyin': '抖音', 'weibo': '微博', 'zhihu': '知乎',
  };

  final Map<String, String> _statusLabels = {
    'unprocessed': '未处理', 'processing': '处理中', 'pulled': '已拉取', 'failed': '失败', 'archived': '已归档',
  };

  @override
  void initState() {
    super.initState();
    _selectedPlatforms = Set<String>.from(widget.initialPlatforms);
    _selectedStatuses = Set<String>.from(widget.initialStatuses);
    _authorController = TextEditingController(text: widget.initialAuthor);
    _tagInputController = TextEditingController();
    _dateRange = widget.initialDateRange;
    _selectedTags = Set<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _authorController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _resetAll() {
    setState(() {
      _selectedPlatforms.clear();
      _selectedStatuses.clear();
      _authorController.clear();
      _tagInputController.clear();
      _dateRange = null;
      _selectedTags.clear();
      _tagSuggestions = [];
    });
  }

  void _onTagInputChanged(String value, List<String> globalTags) {
    if (value.isEmpty) {
      setState(() => _tagSuggestions = []);
      return;
    }
    final suggestions = globalTags
        .where((t) => t.toLowerCase().contains(value.toLowerCase()) && !_selectedTags.contains(t))
        .take(10)
        .toList();
    setState(() => _tagSuggestions = suggestions);
  }

  void _addTag(String tag) {
    setState(() {
      _selectedTags.add(tag);
      _tagInputController.clear();
      _tagSuggestions = [];
    });
  }

  bool _isPresetRange(DateTimeRange range) {
    final now = DateTime.now();
    final presetDays = [1, 7, 30];
    for (final days in presetDays) {
      final presetStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
      if (range.start.year == presetStart.year && 
          range.start.month == presetStart.month && 
          range.start.day == presetStart.day) {
        return true;
      }
    }
    return false;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 0.5,
      )),
    );
  }

  Widget _buildChoiceChip(String label, bool isSelected, ValueChanged<bool> onSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      showCheckmark: false,
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: const StadiumBorder(),
      side: BorderSide(
        color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
        width: isSelected ? 1.5 : 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allTagsAsync = ref.watch(allTagsProvider);
    final globalTags = allTagsAsync.value?.map((e) => e.name).toList() ?? [];

    return Dialog(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.tune_rounded, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Text('筛选收藏内容', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton.filledTonal(
                    onPressed: _resetAll,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: '重置所有',
                    style: IconButton.styleFrom(foregroundColor: colorScheme.error),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('内容平台'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _platforms.map((p) => _buildChoiceChip(
                          _platformLabels[p] ?? p.toUpperCase(),
                          _selectedPlatforms.contains(p),
                          (selected) => setState(() => selected ? _selectedPlatforms.add(p) : _selectedPlatforms.remove(p)),
                        )).toList(),
                      ),

                      _buildSectionHeader('处理状态'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _statuses.map((s) => _buildChoiceChip(
                          _statusLabels[s] ?? s,
                          _selectedStatuses.contains(s),
                          (selected) => setState(() => selected ? _selectedStatuses.add(s) : _selectedStatuses.remove(s)),
                        )).toList(),
                      ),

                      _buildSectionHeader('标签筛选'),
                      if (_selectedTags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedTags.map((tag) => InputChip(
                              label: Text('#$tag'),
                              onDeleted: () => setState(() => _selectedTags.remove(tag)),
                              deleteIcon: Icon(Icons.close_rounded, size: 14, color: colorScheme.onPrimaryContainer),
                              shape: const StadiumBorder(),
                              backgroundColor: colorScheme.primaryContainer,
                              labelStyle: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                              side: BorderSide(color: colorScheme.primary, width: 1.5),
                            )).toList(),
                          ),
                        ),
                      _buildTextField(
                        controller: _tagInputController,
                        label: '搜索标签',
                        hint: '输入关键词搜索并添加...',
                        icon: Icons.tag_rounded,
                        onChanged: (v) => _onTagInputChanged(v, globalTags),
                        suffixIcon: allTagsAsync.isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                      ),
                      if (_tagInputController.text.isNotEmpty && _tagSuggestions.isEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              '无匹配标签',
                              style: TextStyle(color: colorScheme.outline),
                            ),
                          ),
                        ),
                      if (_tagSuggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _tagSuggestions.map((tag) => ActionChip(
                              label: Text(tag),
                              onPressed: () => _addTag(tag),
                              shape: const StadiumBorder(),
                              backgroundColor: colorScheme.surface,
                              side: BorderSide(color: colorScheme.outlineVariant),
                            )).toList(),
                          ),
                        ),

                      _buildSectionHeader('作者过滤'),
                      _buildTextField(
                        controller: _authorController,
                        label: '作者名称',
                        hint: '包含特定的作者关键词',
                        icon: Icons.person_search_rounded,
                      ),

                      _buildSectionHeader('时间范围'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip('全部时间', _dateRange == null, (s) => setState(() => _dateRange = null)),
                          _buildDatePresetChip('今天', 0),
                          _buildDatePresetChip('过去 7 天', 7),
                          _buildDatePresetChip('过去 30 天', 30),
                          ActionChip(
                            label: Text(_dateRange != null && !_isPresetRange(_dateRange!)
                                ? DateFormat('yyyy-MM-dd').format(_dateRange!.start)
                                : '自定义日期'),
                            avatar: const Icon(Icons.calendar_today_rounded, size: 16),
                            onPressed: _showExpressiveDatePicker,
                            shape: const StadiumBorder(),
                            backgroundColor: (_dateRange != null && !_isPresetRange(_dateRange!)) ? colorScheme.primaryContainer : null,
                            labelStyle: TextStyle(
                              color: (_dateRange != null && !_isPresetRange(_dateRange!)) ? colorScheme.onPrimaryContainer : null,
                              fontWeight: (_dateRange != null && !_isPresetRange(_dateRange!)) ? FontWeight.bold : null,
                            ),
                            side: BorderSide(color: (_dateRange != null && !_isPresetRange(_dateRange!)) ? colorScheme.primary : colorScheme.outlineVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop({
                          'platforms': _selectedPlatforms.toList(),
                          'statuses': _selectedStatuses.toList(),
                          'author': _authorController.text.trim().isEmpty ? null : _authorController.text.trim(),
                          'dateRange': _dateRange,
                          'tags': _selectedTags.toList(),
                        });
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('应用筛选条件'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
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
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildDatePresetChip(String label, int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
    final range = DateTimeRange(start: start, end: now);
    final isSelected = _dateRange != null && _isPresetRange(_dateRange!) && 
                      _dateRange!.start.day == start.day && _dateRange!.duration.inDays == days;
    
    return _buildChoiceChip(label, isSelected, (s) => setState(() => _dateRange = s ? range : null));
  }

  void _showExpressiveDatePicker() async {
    final colorScheme = Theme.of(context).colorScheme;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      locale: const Locale('zh', 'CN'),
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400,
              maxHeight: 560,
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: colorScheme.copyWith(
                  primary: colorScheme.primary,
                  onPrimary: colorScheme.onPrimary,
                  surface: colorScheme.surface,
                  onSurface: colorScheme.onSurface,
                ),
                dialogTheme: DialogThemeData(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
              child: child!,
            ),
          ),
        );
      },
    );
    if (picked != null) setState(() => _dateRange = picked);
  }
}