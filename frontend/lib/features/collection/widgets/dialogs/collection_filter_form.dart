import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/widgets/predictive_back_dialog.dart';
import '../../providers/tag_provider.dart';
import '../../../../theme/design_tokens.dart';

class CollectionFilterForm extends ConsumerStatefulWidget {
  final List<String> initialPlatforms;
  final List<String> initialStatuses;
  final String? initialAuthor;
  final DateTimeRange? initialDateRange;
  final List<String> initialTags;
  final List<String> availableTags;
  final String initialSearchMode;
  final int initialSemanticTopK;
  final String initialSemanticScope;

  const CollectionFilterForm({
    super.key,
    this.initialPlatforms = const [],
    this.initialStatuses = const [],
    this.initialAuthor,
    this.initialDateRange,
    this.initialTags = const [],
    this.availableTags = const [],
    this.initialSearchMode = 'keyword',
    this.initialSemanticTopK = 20,
    this.initialSemanticScope = 'library',
  });

  @override
  ConsumerState<CollectionFilterForm> createState() =>
      _CollectionFilterFormState();
}

class _CollectionFilterFormState extends ConsumerState<CollectionFilterForm> {
  final _bodyKey = GlobalKey();
  late Set<String> _selectedPlatforms;
  late Set<String> _selectedStatuses;
  late TextEditingController _authorController;
  late TextEditingController _tagInputController;
  late DateTimeRange? _dateRange;
  late Set<String> _selectedTags;
  late String _searchMode;
  late double _semanticTopK;
  late String _semanticScope;

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
    'parse_success',
    'parse_failed',
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
    'parse_success': '解析成功',
    'parse_failed': '解析失败',
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
    _searchMode = widget.initialSearchMode == 'semantic'
        ? 'semantic'
        : 'keyword';
    _semanticTopK = widget.initialSemanticTopK.toDouble().clamp(1.0, 100.0);
    _semanticScope =
        ['library', 'discovery', 'all'].contains(widget.initialSemanticScope)
        ? widget.initialSemanticScope
        : 'library';
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
      _searchMode = 'keyword';
      _semanticTopK = 20;
      _semanticScope = 'library';
    });
  }

  void _addTag(String tag) {
    setState(() {
      _selectedTags.add(tag);
      _tagInputController.clear();
    });
  }

  int? _presetDays(DateTimeRange range) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (!DateUtils.isSameDay(range.end, today)) return null;
    for (final days in [0, 7, 30]) {
      if (DateUtils.isSameDay(
        range.start,
        today.subtract(Duration(days: days)),
      )) {
        return days;
      }
    }
    return null;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildChoiceChip(
    String label,
    bool isSelected,
    ValueChanged<bool> onSelected,
  ) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: onSelected,
      showCheckmark: true,
      side: isSelected
          ? BorderSide.none
          : BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
  }

  Widget _buildFilterChip(
    String label,
    bool isSelected,
    ValueChanged<bool> onSelected,
  ) => FilterChip(
    label: Text(label),
    selected: isSelected,
    onSelected: onSelected,
    showCheckmark: true,
    side: isSelected
        ? BorderSide.none
        : BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allTagsAsync = ref.watch(allTagsProvider);
    final tagQuery = _tagInputController.text.trim().toLowerCase();
    final tagSuggestions = tagQuery.isEmpty
        ? const <String>[]
        : (allTagsAsync.value ?? const <TagInfo>[])
              .map((tag) => tag.name)
              .where(
                (tag) =>
                    tag.toLowerCase().contains(tagQuery) &&
                    !_selectedTags.contains(tag),
              )
              .take(10)
              .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortHeight = constraints.maxHeight < 360;
        final minimalHeight = constraints.maxHeight < 180;
        final header = <Widget>[
          Row(
            children: [
              Expanded(
                child: Text(
                  '筛选收藏',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭筛选',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!minimalHeight) ...header,
              Expanded(
                child: SingleChildScrollView(
                  key: _bodyKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (minimalHeight)
                        Column(children: header)
                      else
                        const SizedBox.shrink(),
                      _buildSectionHeader('内容平台'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _platforms
                            .map(
                              (p) => _buildFilterChip(
                                _platformLabels[p] ?? p.toUpperCase(),
                                _selectedPlatforms.contains(p),
                                (selected) => setState(
                                  () => selected
                                      ? _selectedPlatforms.add(p)
                                      : _selectedPlatforms.remove(p),
                                ),
                              ),
                            )
                            .toList(),
                      ),

                      _buildSectionHeader('处理状态'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _statuses
                            .map(
                              (s) => _buildFilterChip(
                                _statusLabels[s] ?? s,
                                _selectedStatuses.contains(s),
                                (selected) => setState(
                                  () => selected
                                      ? _selectedStatuses.add(s)
                                      : _selectedStatuses.remove(s),
                                ),
                              ),
                            )
                            .toList(),
                      ),

                      _buildSectionHeader('标签'),
                      if (_selectedTags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedTags
                                .map(
                                  (tag) => Tooltip(
                                    message: tag,
                                    child: Chip(
                                      label: Text(
                                        '#$tag',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onDeleted: () => setState(
                                        () => _selectedTags.remove(tag),
                                      ),
                                      deleteButtonTooltipMessage: '移除标签 $tag',
                                      backgroundColor:
                                          colorScheme.secondaryContainer,
                                      labelStyle: TextStyle(
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                      side: BorderSide.none,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      _buildTextField(
                        controller: _tagInputController,
                        label: '添加标签',
                        hint: '搜索已有标签',
                        icon: Icons.tag_rounded,
                        onChanged: (_) => setState(() {}),
                        suffixIcon: allTagsAsync.isLoading
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      if (tagQuery.isNotEmpty &&
                          !allTagsAsync.isLoading &&
                          !allTagsAsync.hasError &&
                          tagSuggestions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '没有可添加的匹配标签',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (allTagsAsync.hasError)
                        TextButton.icon(
                          onPressed: () => ref.invalidate(allTagsProvider),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('标签加载失败，重试'),
                        ),
                      if (tagSuggestions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: tagSuggestions
                                .map(
                                  (tag) => Tooltip(
                                    message: tag,
                                    child: ActionChip(
                                      side: BorderSide(
                                        color: colorScheme.outlineVariant,
                                      ),
                                      avatar: const Icon(
                                        Icons.add_rounded,
                                        size: 18,
                                      ),
                                      label: Text(
                                        tag,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onPressed: () => _addTag(tag),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: _authorController,
                        label: '作者',
                        hint: '输入作者名称',
                        icon: Icons.person_search_rounded,
                      ),

                      _buildSectionHeader('时间范围'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip(
                            '全部时间',
                            _dateRange == null,
                            (s) => setState(() => _dateRange = null),
                          ),
                          _buildDatePresetChip('今天', 0),
                          _buildDatePresetChip('过去 7 天', 7),
                          _buildDatePresetChip('过去 30 天', 30),
                          ActionChip(
                            label: const Text('自定义日期'),
                            avatar: const Icon(
                              Icons.calendar_today_rounded,
                              size: 16,
                            ),
                            onPressed: _showExpressiveDatePicker,
                            backgroundColor:
                                (_dateRange != null &&
                                    _presetDays(_dateRange!) == null)
                                ? colorScheme.primaryContainer
                                : null,
                            labelStyle: TextStyle(
                              color:
                                  (_dateRange != null &&
                                      _presetDays(_dateRange!) == null)
                                  ? colorScheme.onPrimaryContainer
                                  : null,
                              fontWeight:
                                  (_dateRange != null &&
                                      _presetDays(_dateRange!) == null)
                                  ? FontWeight.bold
                                  : null,
                            ),
                            side: BorderSide(
                              color:
                                  (_dateRange != null &&
                                      _presetDays(_dateRange!) == null)
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                            ),
                          ),
                        ],
                      ),
                      if (_dateRange != null &&
                          _presetDays(_dateRange!) == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '${DateFormat.yMd('zh_CN').format(_dateRange!.start)} — '
                            '${DateFormat.yMd('zh_CN').format(_dateRange!.end)}',
                          ),
                        ),
                      _buildSectionHeader('搜索模式'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChoiceChip('关键词', _searchMode == 'keyword', (
                            selected,
                          ) {
                            if (selected) {
                              setState(() => _searchMode = 'keyword');
                            }
                          }),
                          _buildChoiceChip('语义', _searchMode == 'semantic', (
                            selected,
                          ) {
                            if (selected) {
                              setState(() => _searchMode = 'semantic');
                            }
                          }),
                        ],
                      ),
                      if (_searchMode == 'semantic') ...[
                        const SizedBox(height: 12),
                        Text('检索范围', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildChoiceChip(
                              '收藏库',
                              _semanticScope == 'library',
                              (selected) {
                                if (selected) {
                                  setState(() => _semanticScope = 'library');
                                }
                              },
                            ),
                            _buildChoiceChip(
                              '探索池',
                              _semanticScope == 'discovery',
                              (selected) {
                                if (selected) {
                                  setState(() => _semanticScope = 'discovery');
                                }
                              },
                            ),
                            _buildChoiceChip('全部', _semanticScope == 'all', (
                              selected,
                            ) {
                              if (selected) {
                                setState(() => _semanticScope = 'all');
                              }
                            }),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '最多显示 ${_semanticTopK.round()} 条结果',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Slider(
                          value: _semanticTopK,
                          min: 1,
                          max: 100,
                          divisions: 99,
                          label: _semanticTopK.round().toString(),
                          onChanged: (v) => setState(() => _semanticTopK = v),
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (shortHeight) _buildActions(),
                    ],
                  ),
                ),
              ),
              if (!shortHeight) const Divider(),
              if (!shortHeight) const SizedBox(height: 8),
              if (!shortHeight) _buildActions(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions() => Row(
    children: [
      Expanded(
        child: TextButton(
          onPressed: _resetAll,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('重置'),
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
              'author': _authorController.text.trim().isEmpty
                  ? null
                  : _authorController.text.trim(),
              'dateRange': _dateRange,
              'tags': _selectedTags.toList(),
              'searchMode': _searchMode,
              'semanticTopK': _semanticTopK.round(),
              'semanticScope': _semanticScope,
            });
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('应用筛选'),
        ),
      ),
    ],
  );

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
          borderRadius: AppShape.cardBorder,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShape.cardBorder,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShape.cardBorder,
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildDatePresetChip(String label, int days) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days));
    final range = DateTimeRange(start: start, end: now);
    final isSelected = _dateRange != null && _presetDays(_dateRange!) == days;

    return _buildChoiceChip(
      label,
      isSelected,
      (s) => setState(() => _dateRange = s ? range : null),
    );
  }

  Future<void> _showExpressiveDatePicker() async {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final picked = await showDialog<DateTimeRange>(
      context: context,
      animationStyle: reducedMotion
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppMotion.surfaceEnter,
              reverseDuration: AppMotion.surfaceExit,
              curve: AppMotion.standardCurve,
            ),
      builder: (context) => PredictiveBackDialog(
        child: _DateRangeSurface(initialRange: _dateRange),
      ),
    );
    if (picked != null && mounted) setState(() => _dateRange = picked);
  }
}

class _DateRangeSurface extends StatefulWidget {
  const _DateRangeSurface({required this.initialRange});
  final DateTimeRange? initialRange;

  @override
  State<_DateRangeSurface> createState() => _DateRangeSurfaceState();
}

class _DateRangeSurfaceState extends State<_DateRangeSurface> {
  final _scrollController = ScrollController();
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Size? _lastSize;
  DatePickerEntryMode? _initialEntryMode;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + media.viewInsets.bottom),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scrolling = constraints.maxHeight < 360;
          final surfaceWidth = constraints.maxWidth.clamp(
            0.0,
            constraints.maxHeight < 420 ? AppPane.formMaxWidth : 480.0,
          );
          final surfaceHeight = constraints.maxHeight.clamp(360.0, 600.0);
          final surfaceColor = Theme.of(
            context,
          ).colorScheme.surfaceContainerHigh;
          final shape = RoundedRectangleBorder(
            borderRadius: scrolling ? BorderRadius.zero : AppShape.sheetBorder,
          );
          _initialEntryMode ??= constraints.maxHeight < 420
              ? DatePickerEntryMode.input
              : DatePickerEntryMode.calendar;
          if (_lastSize != constraints.biggest) {
            _lastSize = constraints.biggest;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final focusContext = FocusManager.instance.primaryFocus?.context;
              if (focusContext == null) return;
              BuildContext target = focusContext;
              focusContext.visitAncestorElements((element) {
                if (element.widget is TextField) {
                  target = element;
                  return false;
                }
                return true;
              });
              Scrollable.ensureVisible(target, alignment: 0.5);
            });
          }
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: surfaceWidth,
                maxHeight: 600,
              ),
              child: Material(
                type: scrolling
                    ? MaterialType.canvas
                    : MaterialType.transparency,
                color: scrolling ? surfaceColor : null,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppShape.sheetBorder,
                ),
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: scrolling,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: SizedBox(
                      // The native range form has a fixed minimum layout. Scroll
                      // that layout when the keyboard leaves too little room.
                      height: surfaceHeight,
                      child: MediaQuery(
                        data: media.copyWith(
                          size: Size(surfaceWidth, surfaceHeight),
                          viewInsets: media.viewInsets.copyWith(bottom: 0),
                        ),
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            datePickerTheme: Theme.of(context).datePickerTheme
                                .copyWith(
                                  rangePickerShape: shape,
                                  shape: shape,
                                  elevation: scrolling ? 0 : null,
                                  rangePickerElevation: scrolling ? 0 : null,
                                  backgroundColor: scrolling
                                      ? surfaceColor
                                      : null,
                                  rangePickerBackgroundColor: scrolling
                                      ? surfaceColor
                                      : null,
                                  rangePickerHeaderBackgroundColor: scrolling
                                      ? surfaceColor
                                      : null,
                                ),
                          ),
                          child: Localizations.override(
                            context: context,
                            locale: const Locale('zh', 'CN'),
                            child: DateRangePickerDialog(
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(
                                const Duration(days: 1),
                              ),
                              initialDateRange: widget.initialRange,
                              initialEntryMode: _initialEntryMode!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
