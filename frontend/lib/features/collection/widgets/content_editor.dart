import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/design_tokens.dart';
import '../../../core/widgets/browser_leave_guard.dart';
import '../../../core/widgets/discard_changes_dialog.dart';
import '../models/content.dart';
import '../providers/content_actions_controller.dart';

AnimationStyle _editAnimation(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? AnimationStyle.noAnimation
    : const AnimationStyle(
        duration: AppMotion.surfaceEnter,
        reverseDuration: AppMotion.surfaceExit,
        curve: AppMotion.standardCurve,
      );

class ContentEditor extends ConsumerStatefulWidget {
  final ContentDetail content;

  const ContentEditor({super.key, required this.content});

  @override
  ConsumerState<ContentEditor> createState() => ContentEditorState();
}

class ContentEditorState extends ConsumerState<ContentEditor> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _authorController;
  final _tagInputController = TextEditingController();
  late List<String> _tags;
  late TextEditingController _coverUrlController;
  late bool _isNsfw;
  bool _isLoading = false;
  bool _confirmingExit = false;
  bool _exitAllowed = false;
  final _scrollController = ScrollController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.content.title);
    _descriptionController = TextEditingController(text: widget.content.body);
    _authorController = TextEditingController(text: widget.content.authorName);
    _tags = List.of(widget.content.tags);
    _coverUrlController = TextEditingController(text: widget.content.coverUrl);
    _isNsfw = widget.content.isNsfw;
    for (final controller in [
      _titleController,
      _descriptionController,
      _authorController,
      _tagInputController,
      _coverUrlController,
    ]) {
      controller.addListener(_draftChanged);
    }
  }

  void _draftChanged() => setState(() {});

  Future<void> _requestClose() async {
    if (await confirmExit() && mounted) Navigator.of(context).pop();
  }

  Future<bool> confirmExit() async {
    if (_exitAllowed) return true;
    if (_isLoading || _confirmingExit) return false;
    if (_buildPatch().isEmpty) return true;
    _confirmingExit = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final discard = await showDiscardChangesDialog(
      context,
      title: '放弃未保存的修改？',
      message: '退出后，本次修改不会保存。',
      animationStyle: _editAnimation(context),
    );
    _confirmingExit = false;
    if (discard == true && mounted) {
      setState(() => _exitAllowed = true);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _tagInputController.dispose();
    _coverUrlController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildPatch() {
    final tags = _draftTags;
    final patch = <String, dynamic>{};
    void addTextChange(String key, String value, String? original) {
      final normalized = value.trim();
      if (normalized != (original ?? '').trim()) patch[key] = normalized;
    }

    addTextChange('title', _titleController.text, widget.content.title);
    addTextChange('body', _descriptionController.text, widget.content.body);
    addTextChange(
      'author_name',
      _authorController.text,
      widget.content.authorName,
    );
    addTextChange(
      'cover_url',
      _coverUrlController.text,
      widget.content.coverUrl,
    );
    if (!listEquals(tags, widget.content.tags)) {
      patch['tags'] = tags;
    }
    if (_isNsfw != widget.content.isNsfw) patch['is_nsfw'] = _isNsfw;
    return patch;
  }

  List<String> get _draftTags {
    final tags = List.of(_tags);
    for (final value in _tagInputController.text.split(RegExp(r'[,，\n]'))) {
      final tag = value.trim();
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
    }
    return tags;
  }

  void _addTags() {
    setState(() {
      _tags = _draftTags;
      _tagInputController.clear();
    });
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final patch = _buildPatch();
    if (patch.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = '没有需要保存的修改';
      });
      return;
    }
    final result = await ref
        .read(contentActionsProvider.notifier)
        .updateContent(widget.content.id, patch);

    if (!mounted) return;
    if (result.ok) {
      setState(() => _exitAllowed = true);
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.message;
      });
    }
  }

  Widget _saveAction() => FilledButton(
    onPressed: _isLoading || _buildPatch().isEmpty ? null : _submit,
    child: _isLoading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Text('保存'),
  );

  InputDecoration _documentDecoration(String label, bool short) =>
      InputDecoration(
        labelText: label,
        floatingLabelBehavior: short
            ? FloatingLabelBehavior.never
            : FloatingLabelBehavior.always,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(vertical: short ? 4 : 12),
      );

  Widget _fields(ThemeData theme, double contentWidth, bool short) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: _titleController,
        decoration: _documentDecoration('标题', short),
        style: short
            ? theme.textTheme.bodyLarge
            : theme.textTheme.headlineSmall,
        enabled: !_isLoading,
        minLines: 1,
        maxLines: null,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _descriptionController,
        decoration: _documentDecoration('正文', short),
        enabled: !_isLoading,
        minLines: 8,
        maxLines: null,
      ),
      const SizedBox(height: AppSpacing.lg),
      Text('标签', style: theme.textTheme.labelLarge),
      const SizedBox(height: AppSpacing.xs),
      if (_tags.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (var index = 0; index < _tags.length; index++)
              Tooltip(
                message: _tags[index],
                child: Chip(
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: (contentWidth - 88).clamp(0, double.infinity),
                    ),
                    child: Text(_tags[index], overflow: TextOverflow.ellipsis),
                  ),
                  deleteButtonTooltipMessage: '移除标签 ${_tags[index]}',
                  onDeleted: _isLoading
                      ? null
                      : () => setState(() => _tags.removeAt(index)),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
      TextField(
        controller: _tagInputController,
        decoration: InputDecoration(
          labelText: '添加标签',
          hintText: '用逗号或换行分隔',
          suffixIcon: IconButton(
            tooltip: '添加标签',
            onPressed: _isLoading || _tagInputController.text.trim().isEmpty
                ? null
                : _addTags,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        minLines: 1,
        maxLines: short ? 1 : 3,
        enabled: !_isLoading,
      ),
      const SizedBox(height: AppSpacing.md),
      ExpansionTile(
        title: const Text('来源信息'),
        expansionAnimationStyle: _editAnimation(context),
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
        maintainState: true,
        children: [
          TextField(
            controller: _authorController,
            decoration: const InputDecoration(labelText: '作者'),
            enabled: !_isLoading,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _coverUrlController,
            decoration: const InputDecoration(labelText: '封面图片地址'),
            enabled: !_isLoading,
            keyboardType: TextInputType.url,
            minLines: 1,
            maxLines: short ? 1 : 3,
          ),
        ],
      ),
      SwitchListTile(
        title: const Text('标记为 NSFW'),
        value: _isNsfw,
        onChanged: _isLoading ? null : (val) => setState(() => _isNsfw = val),
        contentPadding: EdgeInsets.zero,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return BrowserLeaveGuard(
      enabled: !_exitAllowed && (_isLoading || _buildPatch().isNotEmpty),
      child: PopScope<bool>(
        canPop: _exitAllowed || (!_isLoading && _buildPatch().isEmpty),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestClose();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('编辑内容'),
            leading: IconButton(
              tooltip: '返回',
              icon: const BackButtonIcon(),
              onPressed: _isLoading ? null : _requestClose,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _saveAction(),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth.clamp(
                        0.0,
                        AppPane.readableMaxWidth,
                      );
                      return Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: width,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(20),
                            child: _fields(
                              Theme.of(context),
                              width - 40,
                              constraints.maxHeight < 300,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
