import 'package:material_ui/material_ui.dart';
import 'package:gap/gap.dart';

import '../../core/layout/app_page_body.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/app_filter_menu.dart';
import '../discovery/models/discovery_models.dart';

class SourceEditor extends StatefulWidget {
  final VoidCallback onClose;
  final DiscoverySource? initialSource;
  final Future<void> Function(DiscoverySource) onSave;
  final Future<void> Function()? onDelete;

  const SourceEditor({
    super.key,
    required this.onClose,
    this.initialSource,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<SourceEditor> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _categoryController;
  late String _kind;
  late int _interval;
  String? _pendingAction;
  String? _error;

  bool get _busy => _pendingAction != null;

  Future<void> _runAction(String action, Future<void> Function() submit) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _pendingAction = action;
      _error = null;
    });
    try {
      await submit();
      if (mounted) widget.onClose();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingAction = null;
        _error = formatApiErrorMessage(
          error,
          fallbackMessage: action == 'delete' ? '来源删除失败，请稍后重试' : '来源保存失败，请稍后重试',
          includeRequestId: false,
        );
      });
    }
  }

  // 各来源类型的 URL 输入提示
  static const Map<String, _KindMeta> _kindMeta = {
    'rss': _KindMeta(
      label: 'RSS',
      urlLabel: 'RSS 订阅地址',
      urlHint: 'https://example.com/rss.xml',
    ),
    'telegram_channel': _KindMeta(
      label: 'Telegram 频道',
      urlLabel: 'Telegram 频道链接',
      urlHint: 'https://t.me/channelname',
    ),
  };

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialSource?.name ?? '',
    );
    _urlController = TextEditingController(
      text: widget.initialSource?.config['url'] ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.initialSource?.config['category'] ?? '',
    );
    _kind = widget.initialSource?.kind ?? 'rss';
    _interval = widget.initialSource?.syncIntervalMinutes ?? 60;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta[_kind]!;
    final intervals = {15, 30, 60, 120, 360, 1440, _interval}.toList()..sort();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _busy ? null : widget.onClose),
          title: Text(widget.initialSource == null ? '添加来源' : '编辑来源'),
        ),
        body: AppPageBody(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AbsorbPointer(
                absorbing: _busy,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.initialSource == null)
                      AppFilterMenu(
                        label: '来源类型',
                        value: _kind,
                        options: {
                          for (final entry in _kindMeta.entries)
                            entry.key: entry.value.label,
                        },
                        onOpened: () => FocusScope.of(context).unfocus(),
                        onSelected: (value) => setState(() => _kind = value),
                      )
                    else
                      Text(
                        '来源类型：${meta.label}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const Gap(16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        hintText: '如：IT之家',
                      ),
                    ),
                    const Gap(16),
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: meta.urlLabel,
                        hintText: meta.urlHint,
                      ),
                    ),
                    const Gap(16),
                    TextField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: '分类标签（可选）',
                        hintText: '如：科技、新闻',
                      ),
                    ),
                    const Gap(16),
                    AppFilterMenu(
                      label: '同步频率',
                      value: '$_interval',
                      options: {
                        for (final minutes in intervals)
                          '$minutes': _sourceIntervalLabel(minutes),
                      },
                      onOpened: () => FocusScope.of(context).unfocus(),
                      onSelected: (value) =>
                          setState(() => _interval = int.parse(value)),
                    ),
                    if (_error != null) ...[
                      const Gap(16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(24),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 12,
                overflowSpacing: 8,
                children: [
                  if (widget.onDelete != null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _runAction('delete', widget.onDelete!),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: Text(_pendingAction == 'delete' ? '删除中…' : '删除'),
                    ),
                  TextButton(
                    onPressed: _busy ? null : () => widget.onClose(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            final url = _urlController.text.trim();
                            final category = _categoryController.text.trim();
                            final config = <String, dynamic>{
                              ...?widget.initialSource?.config,
                              'url': url,
                            };
                            config.remove('category');
                            if (category.isNotEmpty) {
                              config['category'] = category;
                            }

                            final source = DiscoverySource(
                              id: widget.initialSource?.id ?? 0,
                              kind: _kind,
                              name: _nameController.text.trim(),
                              enabled: widget.initialSource?.enabled ?? true,
                              config: config,
                              syncIntervalMinutes: _interval,
                              createdAt:
                                  widget.initialSource?.createdAt ??
                                  DateTime.now(),
                            );
                            _runAction('save', () => widget.onSave(source));
                          },
                    child: Text(_pendingAction == 'save' ? '保存中…' : '保存'),
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

/// 来源类型的元数据，用于驱动表单字段
class _KindMeta {
  final String label;
  final String urlLabel;
  final String urlHint;
  const _KindMeta({
    required this.label,
    required this.urlLabel,
    required this.urlHint,
  });
}

String _sourceIntervalLabel(int minutes) =>
    minutes % 60 == 0 ? '${minutes ~/ 60} 小时' : '$minutes 分钟';
