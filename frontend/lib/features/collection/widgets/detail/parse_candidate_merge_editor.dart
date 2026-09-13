import 'package:flutter/material.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/widgets/adaptive_form_dialog.dart';
import '../../../../core/widgets/browser_leave_guard.dart';
import '../../../../core/widgets/discard_changes_dialog.dart';
import '../../../../theme/design_tokens.dart';

class ParseCandidateMergeEditor extends StatefulWidget {
  const ParseCandidateMergeEditor({
    super.key,
    required this.field,
    required this.label,
    required this.initialValue,
    required this.parsedValue,
  });

  final String field;
  final String label;
  final String initialValue;
  final String? parsedValue;

  @override
  State<ParseCandidateMergeEditor> createState() =>
      _ParseCandidateMergeEditorState();
}

class _ParseCandidateMergeEditorState extends State<ParseCandidateMergeEditor> {
  late final TextEditingController _controller;
  final _inputKey = GlobalKey();
  final _inputFocus = FocusNode();
  bool _confirmingExit = false;
  bool _allowExit = false;

  bool get _dirty => _controller.text != widget.initialValue;
  bool get _page => widget.field == 'body';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..addListener(_draftChanged);
  }

  void _draftChanged() => setState(() {});

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _requestClose() async {
    if (_confirmingExit) return;
    if (_dirty && !_allowExit) {
      _confirmingExit = true;
      _inputFocus.unfocus();
      final discard = await showDiscardChangesDialog(
        context,
        title: '放弃未应用的合并？',
        message: '退出后，本次编辑不会保留。',
      );
      _confirmingExit = false;
      if (discard != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _allowExit = true);
    Navigator.of(context).pop();
  }

  void _apply() {
    _inputFocus.unfocus();
    setState(() => _allowExit = true);
    Navigator.of(context).pop(_controller.text);
  }

  Widget _source(BuildContext context) => SelectableText(
    (widget.parsedValue ?? '').trim().isEmpty ? '（空）' : widget.parsedValue!,
    style: Theme.of(context).textTheme.bodyLarge,
  );

  Widget _sourceDisclosure() => ExpansionTile(
    title: const Text('新解析版本'),
    tilePadding: EdgeInsets.zero,
    shape: const RoundedRectangleBorder(borderRadius: AppShape.cardBorder),
    collapsedShape: const RoundedRectangleBorder(
      borderRadius: AppShape.cardBorder,
    ),
    clipBehavior: Clip.antiAlias,
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
    maintainState: true,
    expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: AppMotion.contentSwap,
            curve: AppMotion.standardCurve,
          ),
    children: [_source(context)],
  );

  Widget _input() {
    final input = TextField(
      key: _inputKey,
      controller: _controller,
      focusNode: _inputFocus,
      minLines: _page ? 8 : 1,
      maxLines: _page ? null : 4,
      style: Theme.of(context).textTheme.bodyLarge,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration(
        labelText: _page ? null : '最终保留的${widget.label}',
        alignLabelWithHint: true,
        filled: _page ? false : null,
        border: _page ? InputBorder.none : null,
        enabledBorder: _page ? InputBorder.none : null,
        focusedBorder: _page ? InputBorder.none : null,
        contentPadding: _page ? EdgeInsets.zero : null,
      ),
    );
    if (!_page) return input;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '最终保留的${widget.label}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(label: '最终保留的${widget.label}', child: input),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final editor = _input();
    final content = _page
        ? Scaffold(
            appBar: AppBar(
              title: Text('合并${widget.label}'),
              toolbarHeight: WindowMetrics.of(context).heightClass.isCompact
                  ? 48
                  : null,
              leading: IconButton(
                tooltip: '返回',
                icon: const BackButtonIcon(),
                onPressed: _requestClose,
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: IconButton.filled(
                    tooltip: '应用合并内容',
                    onPressed: _apply,
                    icon: const Icon(Icons.check_rounded),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppPane.workspaceMaxWidth,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(16) / 16;
                      final sideBySide =
                          constraints.maxWidth >= 760 * textScale &&
                          constraints.maxHeight >= 480;
                      if (sideBySide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '新解析版本',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    _source(context),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: editor,
                              ),
                            ),
                          ],
                        );
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sourceDisclosure(),
                            const SizedBox(height: AppSpacing.md),
                            editor,
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          )
        : AdaptiveFormDialog(
            title: '合并${widget.label}',
            contentBuilder: (context, width, short) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                editor,
                const SizedBox(height: AppSpacing.sm),
                _sourceDisclosure(),
              ],
            ),
            actions: OverflowBar(
              spacing: AppSpacing.xs,
              overflowSpacing: AppSpacing.xs,
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _requestClose, child: const Text('取消')),
                FilledButton(onPressed: _apply, child: const Text('应用合并内容')),
              ],
            ),
          );
    return BrowserLeaveGuard(
      enabled: _dirty && !_allowExit,
      child: PopScope<String>(
        canPop: !_dirty || _allowExit,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _requestClose();
        },
        child: content,
      ),
    );
  }
}
