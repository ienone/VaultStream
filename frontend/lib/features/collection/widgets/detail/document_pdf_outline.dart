import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../../../../theme/design_tokens.dart';
import '../../../../core/widgets/predictive_back_dialog.dart';

class DocumentPdfOutline extends StatefulWidget {
  const DocumentPdfOutline({
    super.key,
    required this.document,
    required this.pageNumber,
    required this.onSelected,
  });
  final PdfDocument document;
  final int pageNumber;
  final ValueChanged<int> onSelected;

  @override
  State<DocumentPdfOutline> createState() => _DocumentPdfOutlineState();
}

class _DocumentPdfOutlineState extends State<DocumentPdfOutline> {
  late Future<List<PdfOutlineNode>> _outline = widget.document.loadOutline();

  @override
  void didUpdateWidget(DocumentPdfOutline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) {
      _outline = widget.document.loadOutline();
    }
  }

  Iterable<({PdfOutlineNode node, int depth})> _entries(
    List<PdfOutlineNode> nodes, [
    int depth = 0,
  ]) sync* {
    for (final node in nodes) {
      yield (node: node, depth: depth);
      yield* _entries(node.children, depth + 1);
    }
  }

  Future<void> _open(List<PdfOutlineNode> nodes) async {
    final entries = _entries(nodes).toList(growable: false);
    final page = await showDialog<int>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => PredictiveBackDialog(
        child: Dialog(
          insetPadding: const EdgeInsets.all(AppSpacing.md),
          clipBehavior: Clip.antiAlias,
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
                          '目录',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭目录',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final target = entry.node.dest?.pageNumber;
                      final valid =
                          target != null &&
                          target >= 1 &&
                          target <= widget.document.pages.length;
                      return ListTile(
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppShape.cardBorder,
                        ),
                        contentPadding: EdgeInsetsDirectional.only(
                          start: 8 + entry.depth.clamp(0, 4) * 12.0,
                          end: 8,
                        ),
                        title: Text(
                          entry.node.title,
                          style: entry.depth == 0
                              ? Theme.of(context).textTheme.titleSmall
                              : Theme.of(context).textTheme.bodyMedium,
                        ),
                        subtitle: valid
                            ? Text(
                                '第 $target 页',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              )
                            : target != null
                            ? const Text('此目录项的页码不可用')
                            : null,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        selected: valid && target == widget.pageNumber,
                        onTap: valid
                            ? () => Navigator.pop(context, target)
                            : null,
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
    if (mounted && page != null) widget.onSelected(page);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PdfOutlineNode>>(
    future: _outline,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return IconButton(
          tooltip: '目录读取失败，点击重试',
          icon: const Icon(Icons.refresh),
          onPressed: () =>
              setState(() => _outline = widget.document.loadOutline()),
        );
      }
      final nodes = snapshot.data;
      if (nodes == null || nodes.isEmpty) return const SizedBox.shrink();
      return TextButton.icon(
        label: const Text('目录'),
        icon: const Icon(Icons.toc),
        onPressed: () => _open(nodes),
      );
    },
  );
}
