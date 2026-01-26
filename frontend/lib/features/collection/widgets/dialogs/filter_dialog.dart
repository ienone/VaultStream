import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FilterDialog extends ConsumerStatefulWidget {
  final String? initialPlatform;
  final String? initialStatus;
  final String? initialAuthor;
  final DateTimeRange? initialDateRange;
  final List<String> initialTags;
  final List<String> availableTags;

  const FilterDialog({
    super.key,
    this.initialPlatform,
    this.initialStatus,
    this.initialAuthor,
    this.initialDateRange,
    this.initialTags = const [],
    this.availableTags = const [],
  });

  @override
  ConsumerState<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends ConsumerState<FilterDialog> {
  late String? _platform;
  late String? _status;
  late TextEditingController _authorController;
  late DateTimeRange? _dateRange;
  late Set<String> _selectedTags;

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
    _platform = widget.initialPlatform;
    _status = widget.initialStatus;
    _authorController = TextEditingController(text: widget.initialAuthor);
    _dateRange = widget.initialDateRange;
    _selectedTags = Set<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _authorController.dispose();
    super.dispose();
  }

  void _resetAll() {
    setState(() {
      _platform = null;
      _status = null;
      _authorController.clear();
      _dateRange = null;
      _selectedTags.clear();
    });
  }

  bool _isPresetRange(DateTimeRange range) {
    final now = DateTime.now();
    final presetDays = [1, 7, 30, 90, 180, 365];
    for (final days in presetDays) {
      final presetStart = now.subtract(Duration(days: days));
      if ((range.start.difference(presetStart).inHours).abs() < 24 &&
          (range.end.difference(now).inHours).abs() < 24) {
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

    return Dialog(
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
                          final isSelected = _platform == p;
                          return FilterChip(
                            label: Text(_platformLabels[p] ?? p.toUpperCase()),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _platform = selected ? p : null;
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
                          final isSelected = _status == s;
                          return FilterChip(
                            label: Text(_statusLabels[s] ?? s),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _status = selected ? s : null;
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

                      // Tags (multi-select)
                      if (widget.availableTags.isNotEmpty) ...[
                        Text('标签', style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        )),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.availableTags.map((tag) {
                            final isSelected = _selectedTags.contains(tag);
                            return FilterChip(
                              label: Text('#$tag'),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedTags.add(tag);
                                  } else {
                                    _selectedTags.remove(tag);
                                  }
                                });
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

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

                      // Date range - 快捷选项
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
                            start: DateTime.now().subtract(const Duration(days: 1)),
                            end: DateTime.now(),
                          )),
                          _buildDateChip('本周', DateTimeRange(
                            start: DateTime.now().subtract(const Duration(days: 7)),
                            end: DateTime.now(),
                          )),
                          _buildDateChip('本月', DateTimeRange(
                            start: DateTime.now().subtract(const Duration(days: 30)),
                            end: DateTime.now(),
                          )),
                          _buildDateChip('三个月', DateTimeRange(
                            start: DateTime.now().subtract(const Duration(days: 90)),
                            end: DateTime.now(),
                          )),
                          _buildDateChip('半年', DateTimeRange(
                            start: DateTime.now().subtract(const Duration(days: 180)),
                            end: DateTime.now(),
                          )),
                          _buildDateChip('一年', DateTimeRange(
                            start: DateTime.now().subtract(const Duration(days: 365)),
                            end: DateTime.now(),
                          )),
                          // 自定义选项
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
                              );
                              if (picked != null) {
                                setState(() => _dateRange = picked);
                              }
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
                          'platform': _platform,
                          'status': _status,
                          'author': _authorController.text.trim().isEmpty
                              ? null
                              : _authorController.text.trim(),
                          'dateRange': _dateRange,
                          'tags': _selectedTags.toList(),
                        });
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
    );
  }
}
