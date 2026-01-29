import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  final List<String> _platforms = [
    'bilibili',
    'twitter',
    'xiaohongshu',
    'douyin',
    'weibo',
    'zhihu',
  ];

  final List<String> _statuses = [
    'unprocessed',
    'processing',
    'pulled',
    'failed',
    'archived',
  ];

  final Map<String, String> _platformLabels = {
    'bilibili': 'Bilibili',
    'twitter': 'Twitter/X',
    'xiaohongshu': '小红书',
    'douyin': '抖音',
    'weibo': '微博',
    'zhihu': '知乎',
  };

  final Map<String, String> _statusLabels = {
    'unprocessed': '未处理',
    'processing': '处理中',
    'pulled': '已拉取',
    'failed': '失败',
    'archived': '已归档',
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
      _authorController.text = ''; // 显式设置文本
      _tagInputController.text = '';
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
        .where((t) => t.contains(value.toLowerCase()) && !_selectedTags.contains(t))
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

  Widget _buildDateChip(String label, DateTimeRange? range) {
    final isSelected = (range == null && _dateRange == null) ||
        (range != null && _dateRange != null && _isPresetRange(_dateRange!) &&
         range.duration.inDays == _dateRange!.duration.inDays);
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _dateRange = selected ? range : null;
        });
      },
      showCheckmark: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allTagsAsync = ref.watch(allTagsProvider);
    final globalTags = allTagsAsync.value?.map((e) => e.name).toList() ?? [];

    return Material(
      color: Colors.transparent,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.filter_list_rounded, color: colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      '筛选内容',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _resetAll,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('重置'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Platform chips
                        Text('平台', style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _platforms.map((p) {
                            final isSelected = _selectedPlatforms.contains(p);
                            return FilterChip(
                              label: Text(_platformLabels[p] ?? p.toUpperCase()),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedPlatforms.add(p);
                                  } else {
                                    _selectedPlatforms.remove(p);
                                  }
                                });
                              },
                              showCheckmark: false,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // Status chips
                        Text('状态', style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _statuses.map((s) {
                            final isSelected = _selectedStatuses.contains(s);
                            return FilterChip(
                              label: Text(_statusLabels[s] ?? s),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedStatuses.add(s);
                                  } else {
                                    _selectedStatuses.remove(s);
                                  }
                                });
                              },
                              showCheckmark: false,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),

                        // Tags (Search and Select)
                        Text('标签', style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        if (_selectedTags.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _selectedTags.map((tag) => InputChip(
                                label: Text('#$tag'),
                                onDeleted: () => setState(() => _selectedTags.remove(tag)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              )).toList(),
                            ),
                          ),
                        TextField(
                          controller: _tagInputController,
                          onChanged: (v) => _onTagInputChanged(v, globalTags),
                          decoration: InputDecoration(
                            hintText: '搜索并添加标签...',
                            prefixIcon: const Icon(Icons.tag, size: 20),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                        if (_tagSuggestions.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Wrap(
                              spacing: 8,
                              children: _tagSuggestions.map((tag) => ActionChip(
                                label: Text(tag),
                                onPressed: () => _addTag(tag),
                              )).toList(),
                            ),
                          ),
                        const SizedBox(height: 20),

                        // Author
                        TextField(
                          controller: _authorController,
                          decoration: InputDecoration(
                            labelText: '作者',
                            hintText: '包含关键词',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Date range
                        Text('时间范围', style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildDateChip('全部', null),
                            _buildDateChip('今天', DateTimeRange(
                              start: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                              end: DateTime.now(),
                            )),
                            _buildDateChip('过去7天', DateTimeRange(
                              start: DateTime.now().subtract(const Duration(days: 7)),
                              end: DateTime.now(),
                            )),
                            _buildDateChip('过去30天', DateTimeRange(
                              start: DateTime.now().subtract(const Duration(days: 30)),
                              end: DateTime.now(),
                            )),
                            ActionChip(
                              label: Text(_dateRange != null && !_isPresetRange(_dateRange!)
                                  ? '${_dateRange!.start.toString().split(' ')[0]} ~ ${_dateRange!.end.toString().split(' ')[0]}'
                                  : '自定义'),
                              avatar: const Icon(Icons.edit_calendar, size: 18),
                              onPressed: () async {
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  initialDateRange: _dateRange,
                                  builder: (context, child) => Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 520),
                                      child: child,
                                    ),
                                  ),
                                );
                                if (picked != null) {
                                  setState(() => _dateRange = picked);
                                }
                              },
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('应用筛选'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
