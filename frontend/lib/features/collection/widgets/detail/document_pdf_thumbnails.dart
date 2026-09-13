import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../../theme/design_tokens.dart';
import '../../../../core/widgets/predictive_back_dialog.dart';

/// Uses the already open document; browsing pages does not fetch the file again.
class DocumentPdfThumbnails extends StatefulWidget {
  const DocumentPdfThumbnails({
    super.key,
    required this.document,
    required this.pageNumber,
  });

  final PdfDocument document;
  final int pageNumber;

  @override
  State<DocumentPdfThumbnails> createState() => _DocumentPdfThumbnailsState();
}

class _DocumentPdfThumbnailsState extends State<DocumentPdfThumbnails> {
  ScrollController? _controller;
  int? _columns;
  double? _rowExtent;
  double? _viewportHeight;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PredictiveBackDialog(
    child: Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      child: SizedBox(
        width: AppPane.readableMaxWidth,
        height: (MediaQuery.sizeOf(context).height - 32).clamp(0, 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '缩略页',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭缩略页',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final labelStyle = Theme.of(context).textTheme.bodyMedium;
                  final label = TextPainter(
                    text: TextSpan(
                      text: '第 ${widget.document.pages.length} 页',
                      style: labelStyle,
                    ),
                    textScaler: MediaQuery.textScalerOf(context),
                    textDirection: Directionality.of(context),
                  )..layout();
                  final minimumWidth = math.max(128.0, label.width + 24);
                  final labelHeight = label.height;
                  label.dispose();
                  final width = constraints.maxWidth - 24;
                  final columns = ((width + 12) / (minimumWidth + 12))
                      .floor()
                      .clamp(1, 6);
                  final tileWidth = (width - (columns - 1) * 12) / columns;
                  final tileHeight = math.max(
                    labelHeight + 72,
                    math.min(
                      tileWidth * 1.3 + labelHeight + 24,
                      constraints.maxHeight - 24,
                    ),
                  );
                  final current = (widget.pageNumber - 1).clamp(
                    0,
                    widget.document.pages.length - 1,
                  );
                  final rowExtent = tileHeight + 12;
                  if (_controller == null) {
                    _controller = ScrollController(
                      initialScrollOffset: (current ~/ columns) * rowExtent,
                    );
                  } else if (_controller!.hasClients &&
                      _columns != null &&
                      (_columns != columns || _rowExtent != rowExtent)) {
                    final offset = _controller!.offset;
                    final selectedTop = (current ~/ _columns!) * _rowExtent!;
                    final selectedVisible =
                        selectedTop + _rowExtent! > offset &&
                        selectedTop < offset + _viewportHeight!;
                    final anchor = selectedVisible
                        ? current
                        : (offset / _rowExtent!).floor() * _columns!;
                    final target = (anchor ~/ columns) * rowExtent;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !_controller!.hasClients) return;
                      _controller!.jumpTo(
                        target.clamp(0, _controller!.position.maxScrollExtent),
                      );
                    });
                  }
                  _columns = columns;
                  _rowExtent = rowExtent;
                  _viewportHeight = constraints.maxHeight;
                  return GridView.builder(
                    controller: _controller,
                    padding: const EdgeInsets.all(12),
                    itemCount: widget.document.pages.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: tileHeight,
                    ),
                    itemBuilder: (context, index) {
                      final page = widget.document.pages[index];
                      final selected = index + 1 == widget.pageNumber;
                      final colors = Theme.of(context).colorScheme;
                      return Semantics(
                        selected: selected,
                        button: true,
                        label: '第 ${index + 1} 页',
                        excludeSemantics: true,
                        onTap: () => Navigator.pop(context, index + 1),
                        child: Material(
                          color: selected
                              ? colors.secondaryContainer
                              : colors.surfaceContainerLow,
                          borderRadius: AppShape.cardBorder,
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, index + 1),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: AspectRatio(
                                        aspectRatio: page.width / page.height,
                                        child: PdfPageView(
                                          document: widget.document,
                                          pageNumber: index + 1,
                                          backgroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '第 ${index + 1} 页',
                                    style: labelStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
