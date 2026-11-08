import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/app_choice_segments.dart';
import '../../../../core/widgets/app_multi_select.dart';
import '../../../../core/widgets/app_filter_menu.dart';
import '../../providers/tag_provider.dart';
import '../../../search/search_models.dart';

class CollectionFilterForm extends ConsumerStatefulWidget {
  const CollectionFilterForm({super.key, required this.request});
  final UnifiedSearchRequest request;
  @override
  ConsumerState<CollectionFilterForm> createState() =>
      _CollectionFilterFormState();
}

class _CollectionFilterFormState extends ConsumerState<CollectionFilterForm> {
  late Set<String> _platforms, _statuses, _tags;
  late final TextEditingController _author;
  late String _mode;
  late double _topK;
  DateTimeRange? _range;
  bool _dateChanged = false;
  @override
  void initState() {
    super.initState();
    final r = widget.request;
    _platforms = r.platforms.toSet();
    _statuses = r.statuses.toSet();
    _tags = r.tags.toSet();
    _author = TextEditingController(text: r.author);
    _mode = r.mode;
    _topK = r.topK.toDouble().clamp(1, 100);
    if (r.dateFrom != null &&
        r.dateTo != null &&
        !r.dateFrom!.isAfter(r.dateTo!)) {
      _range = DateTimeRange(
        start: r.dateFrom!.toLocal(),
        end: r.dateTo!.toLocal(),
      );
    }
  }

  @override
  void dispose() {
    _author.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _platforms.clear();
    _statuses.clear();
    _tags.clear();
    _author.clear();
    _range = null;
    _dateChanged = true;
  });
  void _apply() {
    final end = _range?.end;
    Navigator.of(context).pop(
      widget.request.copyWith(
        page: 1,
        platforms: _platforms.toList(),
        statuses: _statuses.toList(),
        tags: _tags.toList(),
        author: _author.text.trim().isEmpty ? null : _author.text.trim(),
        dateFrom: _dateChanged ? _range?.start : widget.request.dateFrom,
        dateTo: _dateChanged
            ? (end == null
                  ? null
                  : DateTime(
                      end.year,
                      end.month,
                      end.day + 1,
                    ).subtract(const Duration(microseconds: 1)))
            : widget.request.dateTo,
        mode: _mode,
        topK: _topK.round(),
      ),
    );
  }

  int _preset() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (_range == null) return -1;
    if (DateUtils.isSameDay(_range!.end, today)) {
      for (final days in [0, 7, 30]) {
        if (DateUtils.isSameDay(
          _range!.start,
          today.subtract(Duration(days: days)),
        )) {
          return days;
        }
      }
    }
    return -2;
  }

  Future<void> _pickDates() async {
    final picked = await showDialog<DateTimeRange>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            child: LayoutBuilder(
              builder: (context, box) => MediaQuery(
                data: MediaQuery.of(context).copyWith(size: box.biggest),
                child: DateRangePickerDialog(
                  initialDateRange: _range,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  helpText: '保存日期',
                  saveText: '应用',
                  confirmText: '应用',
                  cancelText: '取消',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = picked;
      _dateChanged = true;
    });
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall),
  );
  Widget _actions() => Row(
    children: [
      TextButton(onPressed: _reset, child: const Text('清除筛选')),
      const Spacer(),
      FilledButton(onPressed: _apply, child: const Text('应用筛选')),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final tagData = ref.watch(allTagsProvider);
    final tagNames = {..._tags, ...?tagData.value?.map((tag) => tag.name)};
    return LayoutBuilder(
      builder: (context, box) {
        final short = box.maxHeight < 360;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '筛选',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heading('处理状态'),
                    AppChoiceSegments<String>(
                      options: const {
                        'unprocessed': '未处理',
                        'processing': '处理中',
                        'parse_success': '成功',
                        'parse_failed': '失败',
                      },
                      selected: _statuses,
                      multiple: true,
                      allowEmpty: true,
                      onChanged: (values) => setState(() => _statuses = values),
                    ),
                    const SizedBox(height: 24),
                    AppMultiSelect(
                      label: '内容平台',
                      hint: '全部平台',
                      options: searchPlatformLabels,
                      selected: _platforms,
                      onChanged: (values) =>
                          setState(() => _platforms = values),
                    ),
                    const SizedBox(height: 24),
                    AppMultiSelect(
                      label: '标签',
                      hint: '不限标签',
                      options: {for (final name in tagNames) name: name},
                      selected: _tags,
                      onChanged: (values) => setState(() => _tags = values),
                    ),
                    if (tagData.hasError)
                      TextButton.icon(
                        onPressed: () => ref.invalidate(allTagsProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('标签加载失败，重试'),
                      ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _author,
                      decoration: const InputDecoration(
                        labelText: '作者',
                        hintText: '不限作者',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AppFilterMenu(
                      label: '保存日期',
                      value: '${_preset()}',
                      options: {
                        '-1': '不限日期',
                        '0': '今天',
                        '7': '最近 7 天',
                        '30': '最近 30 天',
                        '-3': '自选日期范围…',
                        if (_preset() == -2)
                          '-2':
                              '${DateFormat('MM/dd').format(_range!.start)} — ${DateFormat('MM/dd').format(_range!.end)}',
                      },
                      onSelected: (value) {
                        final days = int.parse(value);
                        if (days == -3) {
                          _pickDates();
                          return;
                        }
                        setState(() {
                          final today = DateUtils.dateOnly(DateTime.now());
                          _range = days == -1
                              ? null
                              : DateTimeRange(
                                  start: today.subtract(Duration(days: days)),
                                  end: today,
                                );
                          _dateChanged = true;
                        });
                      },
                    ),
                    if (widget.request.query.trim().isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _heading('搜索方式'),
                      AppChoiceSegments<String>(
                        options: const {'keyword': '关键词', 'semantic': '语义'},
                        selected: {_mode},
                        onChanged: (values) =>
                            setState(() => _mode = values.first),
                      ),
                      if (_mode == 'semantic') ...[
                        const SizedBox(height: 12),
                        Text('最多显示 ${_topK.round()} 条结果'),
                        Slider(
                          value: _topK,
                          min: 1,
                          max: 100,
                          divisions: 99,
                          label: _topK.round().toString(),
                          onChanged: (value) => setState(() => _topK = value),
                        ),
                      ],
                    ],
                    if (short) ...[const SizedBox(height: 16), _actions()],
                  ],
                ),
              ),
            ),
            if (!short)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 24, 16),
                  child: _actions(),
                ),
              ),
          ],
        );
      },
    );
  }
}
