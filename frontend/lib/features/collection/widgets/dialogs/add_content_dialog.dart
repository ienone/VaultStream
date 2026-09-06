import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../theme/design_tokens.dart';
import '../../models/capture_draft.dart';
import '../../providers/content_actions_controller.dart';

class AddContentDialog extends ConsumerStatefulWidget {
  const AddContentDialog({
    super.key,
    this.draft = const CaptureDraft(),
    this.dialogSurface = false,
  });

  final CaptureDraft draft;
  final bool dialogSurface;

  /// 显示添加内容底部弹窗
  static Future<ContentActionResult?> show(
    BuildContext context, {
    CaptureDraft draft = const CaptureDraft(),
  }) {
    final metrics = WindowMetrics.of(context);
    if (metrics.supportsSupportingPane) {
      return showDialog<ContentActionResult>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShape.sheet),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppPane.formMaxWidth,
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: AddContentDialog(draft: draft, dialogSurface: true),
          ),
        ),
      );
    }
    return showModalBottomSheet<ContentActionResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: AppPane.formMaxWidth),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: AddContentDialog(draft: draft),
      ),
    );
  }

  /// 打开统一的应用内链接捕获面，并在成功后提供内容详情入口。
  static Future<void> showAndNotify(BuildContext context) async {
    final router = GoRouter.of(context);
    final result = await show(context);
    if (result == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        action: result.contentId == null
            ? null
            : SnackBarAction(
                label: '查看',
                onPressed: () => router.push('/collection/${result.contentId}'),
              ),
      ),
    );
  }

  @override
  ConsumerState<AddContentDialog> createState() => _AddContentDialogState();
}

class _AddContentDialogState extends ConsumerState<AddContentDialog> {
  late CaptureKind _kind;
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  final _textController = TextEditingController();
  final _noteController = TextEditingController();
  final _tagsController = TextEditingController();
  final List<XFile> _selectedFiles = [];
  bool _isNsfw = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _kind = widget.draft.effectiveInitialKind;
    _urlController.text = widget.draft.url ?? '';
    _titleController.text = widget.draft.title ?? '';
    _textController.text = widget.draft.text ?? '';
    _noteController.text = widget.draft.note ?? '';
    _selectedFiles.addAll(widget.draft.files);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _textController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final primaryInput = switch (_kind) {
      CaptureKind.link => _urlController.text.trim(),
      CaptureKind.text => _textController.text.trim(),
      CaptureKind.file =>
        _selectedFiles.isEmpty ? '' : _selectedFiles.first.name,
    };
    if (primaryInput.isEmpty) {
      setState(
        () => _errorMessage = switch (_kind) {
          CaptureKind.link => '请输入有效的 URL',
          CaptureKind.text => '请输入要保存的文本',
          CaptureKind.file => '请选择要归档的文件',
        },
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final customTags = _tagsController.text
        .split(RegExp(r'[,\s，]'))
        .where((t) => t.isNotEmpty)
        .toList();
    final allTags = customTags.toSet().toList();
    final actions = ref.read(contentActionsProvider.notifier);
    final title = _titleController.text.trim();
    final result = switch (_kind) {
      CaptureKind.link => await actions.createShare(
        url: primaryInput,
        tags: allTags,
        isNsfw: _isNsfw,
        source: widget.draft.source,
        note: _noteController.text,
        clientContext: widget.draft.clientContext,
      ),
      CaptureKind.text => await actions.createText(
        text: primaryInput,
        title: title.isEmpty ? null : title,
        tags: allTags,
        isNsfw: _isNsfw,
        source: widget.draft.source == 'manual_paste'
            ? 'manual_text'
            : widget.draft.source,
        note: _noteController.text,
        clientContext: widget.draft.clientContext,
      ),
      CaptureKind.file => await actions.createFiles(
        files: _selectedFiles,
        title: title.isEmpty ? null : title,
        note: _noteController.text,
        tags: allTags,
        isNsfw: _isNsfw,
        source: widget.draft.source == 'manual_paste'
            ? 'manual_upload'
            : widget.draft.source,
        clientContext: widget.draft.clientContext,
      ),
    };

    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(result);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: widget.dialogSurface
          ? BorderRadius.circular(AppShape.sheet)
          : AppShape.sheetTopBorder,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.dialogSurface) ...[
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(AppShape.pill),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              Text(
                '保存内容',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: SegmentedButton<CaptureKind>(
                  segments: const [
                    ButtonSegment(
                      value: CaptureKind.link,
                      icon: Icon(Icons.link_rounded),
                      label: Text('链接'),
                    ),
                    ButtonSegment(
                      value: CaptureKind.text,
                      icon: Icon(Icons.notes_rounded),
                      label: Text('文本'),
                    ),
                    ButtonSegment(
                      value: CaptureKind.file,
                      icon: Icon(Icons.upload_file_rounded),
                      label: Text('文件'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _isLoading
                      ? null
                      : (selection) => setState(() {
                          _kind = selection.first;
                          _errorMessage = null;
                        }),
                ),
              ),
              const SizedBox(height: 20),

              if (_kind == CaptureKind.link) ...[
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    hintText: 'https://...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link_rounded),
                    isDense: true,
                  ),
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
              ] else if (_kind == CaptureKind.text) ...[
                TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: '原始文本',
                    hintText: '粘贴摘录、笔记或稍后要整理的内容',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 12),
              ] else ...[
                OutlinedButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          final files = await openFiles();
                          if (files.isNotEmpty && mounted) {
                            setState(() {
                              final existingPaths = _selectedFiles
                                  .map((file) => file.path)
                                  .toSet();
                              _selectedFiles.addAll(
                                files.where(
                                  (file) => !existingPaths.contains(file.path),
                                ),
                              );
                              _errorMessage = null;
                            });
                          }
                        },
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(_selectedFiles.isEmpty ? '选择文件' : '继续添加文件'),
                ),
                if (_selectedFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _selectedFiles.length == 1
                        ? '将保存原始文件，可从内容详情重新打开。'
                        : '这 ${_selectedFiles.length} 个文件会作为同一条内容归档。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final file in _selectedFiles)
                        InputChip(
                          label: Text(file.name),
                          onDeleted: _isLoading
                              ? null
                              : () =>
                                    setState(() => _selectedFiles.remove(file)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 20),

              ExpansionTile(
                title: Text(_isNsfw ? '附加信息 · 敏感内容' : '附加信息（可选）'),
                tilePadding: EdgeInsets.zero,
                initiallyExpanded:
                    _noteController.text.isNotEmpty ||
                    _titleController.text.isNotEmpty,
                maintainState: true,
                children: [
                  if (_kind != CaptureKind.link) ...[
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '标题',
                        border: OutlineInputBorder(),
                      ),
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(
                      labelText: '保存说明',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    minLines: 2,
                    maxLines: 4,
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: '标签',
                      hintText: '用空格或逗号分隔',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !_isLoading,
                  ),
                  SwitchListTile(
                    title: const Text('标记为敏感内容'),
                    subtitle: const Text('浏览时默认隐藏'),
                    value: _isNsfw,
                    onChanged: _isLoading
                        ? null
                        : (value) => setState(() => _isNsfw = value),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),

              // 错误信息
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: AppShape.cardMediaBorder,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存'),
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
