import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../providers/document_pdf_provider.dart';
import 'document_pdf_outline.dart';
import 'document_page_jump_dialog.dart';
import '../../../../theme/design_tokens.dart';
import 'document_pdf_thumbnails.dart';

class DocumentPdfPreview extends ConsumerStatefulWidget {
  const DocumentPdfPreview({
    super.key,
    required this.assetId,
    required this.pageNumber,
    required this.onPageChanged,
  });
  final int assetId;
  final int pageNumber;
  final ValueChanged<int> onPageChanged;

  @override
  ConsumerState<DocumentPdfPreview> createState() => _DocumentPdfPreviewState();
}

class _DocumentPdfPreviewState extends ConsumerState<DocumentPdfPreview> {
  Uint8List? _bytes;
  PdfDocumentRefData? _documentRef;

  @override
  Widget build(BuildContext context) {
    final assetId = widget.assetId;
    final pageNumber = widget.pageNumber;
    final onPageChanged = widget.onPageChanged;
    final bytes = ref.watch(documentPdfProvider(assetId));
    Widget failure([String message = '原页预览暂时不可用，可重试或打开原文件。']) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        TextButton(
          onPressed: () => ref.invalidate(documentPdfProvider(assetId)),
          child: const Text('重试预览'),
        ),
      ],
    );
    return bytes.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: LinearProgressIndicator(),
      ),
      error: (error, stack) => failure(
        error is DocumentPdfReadException ? error.message : '原文件读取失败，请重试。',
      ),
      data: (data) {
        if (!identical(data, _bytes)) {
          _bytes = data;
          _documentRef = PdfDocumentRefData(
            data,
            sourceName: 'document-$assetId-${identityHashCode(data)}',
          );
        }
        return PdfDocumentViewBuilder(
          documentRef: _documentRef!,
          errorBuilder: (context, error, stack) => failure(),
          builder: (context, document) {
            if (document == null) return const LinearProgressIndicator();
            final valid =
                pageNumber >= 1 && pageNumber <= document.pages.length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(16) / 16;
                    final navigation = Row(
                      children: [
                        IconButton(
                          tooltip: '上一页',
                          onPressed: valid && pageNumber > 1
                              ? () => onPageChanged(pageNumber - 1)
                              : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: document.pages.isEmpty
                                ? null
                                : () async {
                                    final target = await showDialog<int>(
                                      context: context,
                                      animationStyle:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? AnimationStyle.noAnimation
                                          : null,
                                      builder: (_) => DocumentPageJumpDialog(
                                        pageNumber: pageNumber,
                                        pageCount: document.pages.length,
                                      ),
                                    );
                                    if (context.mounted && target != null) {
                                      onPageChanged(target);
                                    }
                                  },
                            child: Text(
                              valid
                                  ? '第 $pageNumber / ${document.pages.length} 页'
                                  : '选择页码',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '下一页',
                          onPressed: valid && pageNumber < document.pages.length
                              ? () => onPageChanged(pageNumber + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    );
                    final tools = Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        TextButton.icon(
                          label: const Text('缩略页'),
                          icon: const Icon(Icons.grid_view_outlined),
                          onPressed: document.pages.isEmpty
                              ? null
                              : () async {
                                  final target = await showDialog<int>(
                                    context: context,
                                    animationStyle:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? AnimationStyle.noAnimation
                                        : null,
                                    builder: (_) => DocumentPdfThumbnails(
                                      document: document,
                                      pageNumber: pageNumber,
                                    ),
                                  );
                                  if (context.mounted && target != null) {
                                    onPageChanged(target);
                                  }
                                },
                        ),
                        DocumentPdfOutline(
                          document: document,
                          pageNumber: pageNumber,
                          onSelected: onPageChanged,
                        ),
                      ],
                    );
                    if (constraints.maxWidth >= 600 * textScale) {
                      return Row(
                        children: [
                          SizedBox(width: 320 * textScale, child: navigation),
                          const Spacer(),
                          tools,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [navigation, tools],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xs),
                if (!valid)
                  const Text('引用的页码已不存在，请重新选择。')
                else
                  AspectRatio(
                    aspectRatio:
                        document.pages[pageNumber - 1].width /
                        document.pages[pageNumber - 1].height,
                    child: DocumentPdfPage(
                      key: ValueKey('$assetId-$pageNumber'),
                      document: document,
                      pageNumber: pageNumber,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Re-rasterize after zoom settles, keeping the previous image during the gesture.
class DocumentPdfPage extends StatefulWidget {
  const DocumentPdfPage({
    super.key,
    required this.document,
    required this.pageNumber,
  });
  final PdfDocument document;
  final int pageNumber;

  @override
  State<DocumentPdfPage> createState() => _DocumentPdfPageState();
}

class _DocumentPdfPageState extends State<DocumentPdfPage> {
  final _transform = TransformationController();
  double _renderScale = 1;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
    transformationController: _transform,
    maxScale: 5,
    onInteractionEnd: (_) {
      final scale = _transform.value.getMaxScaleOnAxis();
      if (scale != _renderScale) setState(() => _renderScale = scale);
    },
    child: PdfPageView(
      document: widget.document,
      pageNumber: widget.pageNumber,
      backgroundColor: Colors.white,
      pageSizeCallback: (size, page, rotation) {
        final scale = math.min(
          300 / 72,
          math.min(size.width / page.width, size.height / page.height) *
              _renderScale,
        );
        return Size(page.width * scale, page.height * scale);
      },
    ),
  );
}
