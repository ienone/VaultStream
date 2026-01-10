import 'package:flutter/material.dart';

class FilterDialog extends StatefulWidget {
  final String? initialPlatform;
  final String? initialStatus;
  final String? initialAuthor;
  final DateTimeRange? initialDateRange;

  const FilterDialog({
    super.key,
    this.initialPlatform,
    this.initialStatus,
    this.initialAuthor,
    this.initialDateRange,
  });

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late String? _platform;
  late String? _status;
  late TextEditingController _authorController;
  late DateTimeRange? _dateRange;

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

  @override
  void initState() {
    super.initState();
    _platform = widget.initialPlatform;
    _status = widget.initialStatus;
    _authorController = TextEditingController(text: widget.initialAuthor);
    _dateRange = widget.initialDateRange;
  }

  @override
  void dispose() {
    _authorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('筛选内容'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '平台',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _platform,
                isDense: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部')),
                  ..._platforms.map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.toUpperCase()),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _platform = val),
              ),
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: '状态',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _status,
                isDense: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部')),
                  ..._statuses.map(
                    (s) => DropdownMenuItem(value: s, child: Text(s)),
                  ),
                ],
                onChanged: (val) => setState(() => _status = val),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _authorController,
            decoration: const InputDecoration(
              labelText: '作者',
              border: OutlineInputBorder(),
              hintText: '包含关键词',
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
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
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: '时间范围',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.date_range),
              ),
              child: Text(
                _dateRange == null
                    ? '全部'
                    : '${_dateRange!.start.toString().split(' ')[0]} - ${_dateRange!.end.toString().split(' ')[0]}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Reset
            setState(() {
              _platform = null;
              _status = null;
              _authorController.clear();
              _dateRange = null;
            });
          },
          child: const Text('重置'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop({
              'platform': _platform,
              'status': _status,
              'author': _authorController.text.trim().isEmpty
                  ? null
                  : _authorController.text.trim(),
              'dateRange': _dateRange,
            });
          },
          child: const Text('应用'),
        ),
      ],
    );
  }
}
