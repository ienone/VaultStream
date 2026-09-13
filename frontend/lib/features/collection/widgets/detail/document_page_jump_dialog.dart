import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/widgets/adaptive_form_dialog.dart';
import '../../../../theme/design_tokens.dart';

class DocumentPageJumpDialog extends StatefulWidget {
  const DocumentPageJumpDialog({
    super.key,
    required this.pageNumber,
    required this.pageCount,
  });

  final int pageNumber;
  final int pageCount;

  @override
  State<DocumentPageJumpDialog> createState() => _DocumentPageJumpDialogState();
}

class _DocumentPageJumpDialogState extends State<DocumentPageJumpDialog> {
  late final _controller =
      TextEditingController(
          text: widget.pageNumber >= 1 && widget.pageNumber <= widget.pageCount
              ? '${widget.pageNumber}'
              : '',
        )
        ..selection = TextSelection(
          baseOffset: 0,
          extentOffset:
              widget.pageNumber >= 1 && widget.pageNumber <= widget.pageCount
              ? '${widget.pageNumber}'.length
              : 0,
        );
  String? _error;

  void _jump() {
    final page = int.tryParse(_controller.text);
    if (page == null || page < 1 || page > widget.pageCount) {
      setState(() => _error = '请输入 1–${widget.pageCount} 之间的页码');
      return;
    }
    Navigator.pop(context, page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdaptiveFormDialog(
    title: '跳转页码',
    maxWidth: 360,
    contentBuilder: (context, width, short) => TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _jump(),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(
        labelText: '页码',
        helperText: '共 ${widget.pageCount} 页',
        errorText: _error,
        errorMaxLines: 2,
      ),
    ),
    actions: OverflowBar(
      spacing: AppSpacing.xs,
      overflowSpacing: AppSpacing.xs,
      alignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _jump, child: const Text('跳转')),
      ],
    ),
  );
}
