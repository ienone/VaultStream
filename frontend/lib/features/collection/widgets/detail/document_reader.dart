import 'package:flutter/material.dart';
import '../../../../theme/design_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../providers/content_actions_controller.dart';
import '../../providers/document_text_provider.dart';
import 'document_pdf_preview.dart';

class DocumentReader extends ConsumerStatefulWidget {
  const DocumentReader({super.key, required this.contentId});
  final int contentId;

  @override
  ConsumerState<DocumentReader> createState() => _DocumentReaderState();
}

class _DocumentReaderState extends ConsumerState<DocumentReader> {
  int? _assetId;
  int _pageNumber = 1;
  String? _routeKey;
  final _readerKey = GlobalKey();
  bool _scrollToPage = false;
  bool _showOriginal = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final query = GoRouterState.of(context).uri.queryParameters;
    final key = '${query['document_asset']}:${query['page']}';
    if (_routeKey == key) return;
    _routeKey = key;
    _assetId = int.tryParse(query['document_asset'] ?? '');
    _pageNumber = int.tryParse(query['page'] ?? '') ?? 1;
    _scrollToPage = _assetId != null;
  }

  void _select(int assetId, int pageNumber) {
    final uri = GoRouterState.of(context).uri;
    context.replace(
      uri
          .replace(
            queryParameters: {
              ...uri.queryParameters,
              'document_asset': '$assetId',
              'page': '$pageNumber',
            },
          )
          .toString(),
    );
  }

  Future<void> _extract() async {
    final result = await ref
        .read(contentActionsProvider.notifier)
        .extractDocumentText(widget.contentId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        action: result.runId == null
            ? null
            : SnackBarAction(
                label: '查看任务',
                onPressed: () => context.push(
                  '/tasks/${Uri.encodeComponent(result.runId!)}',
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentTextProvider(widget.contentId));
    final pending = ref
        .watch(contentActionsProvider)
        .contains('${widget.contentId}:extract_document');
    return documents.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatApiErrorMessage(error, fallbackMessage: '文档正文读取失败')),
          TextButton(
            onPressed: () =>
                ref.invalidate(documentTextProvider(widget.contentId)),
            child: const Text('重新读取'),
          ),
        ],
      ),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        if (_scrollToPage) {
          _scrollToPage = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = _readerKey.currentContext;
            if (mounted && target != null) Scrollable.ensureVisible(target);
          });
        }
        final selected = items
            .where((item) => item.assetId == _assetId)
            .firstOrNull;
        final document = selected ?? items.first;
        final page = document.pages
            .where((page) => page.number == _pageNumber)
            .firstOrNull;
        final invalidTarget =
            (_assetId != null && selected == null) ||
            (!_showOriginal && page == null && document.pages.isNotEmpty);
        return Padding(
          key: _readerKey,
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('文档阅读', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: pending ? null : _extract,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: Text(document.status == 'pending' ? '提取正文' : '重新提取'),
                  ),
                  IconButton(
                    tooltip: '刷新文档正文',
                    onPressed: () =>
                        ref.invalidate(documentTextProvider(widget.contentId)),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (items.length > 1)
                DropdownButton<int>(
                  borderRadius: AppShape.cardBorder,
                  value: document.assetId,
                  isExpanded: true,
                  items: items
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.assetId,
                          child: Text(
                            item.filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) {
                    if (id != null) _select(id, 1);
                  },
                ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('原页')),
                  ButtonSegment(value: false, label: Text('文本')),
                ],
                selected: {_showOriginal},
                onSelectionChanged: (selection) =>
                    setState(() => _showOriginal = selection.first),
              ),
              const SizedBox(height: 12),
              if (_assetId == null || selected != null)
                Visibility(
                  visible: _showOriginal,
                  maintainState: true,
                  child: DocumentPdfPreview(
                    key: ValueKey(document.assetId),
                    assetId: document.assetId,
                    pageNumber: _pageNumber,
                    onPageChanged: (number) =>
                        _select(document.assetId, number),
                  ),
                ),
              if (!_showOriginal && document.status != 'ready')
                Text(_statusLabel(document)),
              if (invalidTarget) ...[
                const SizedBox(height: 12),
                const Text('引用的文件或页码已不存在，请重新选择。'),
              ],
              if (!_showOriginal && document.pages.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      tooltip: '上一页',
                      onPressed: _pageNumber > 1 && page != null
                          ? () => _select(document.assetId, _pageNumber - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: DropdownButton<int>(
                        borderRadius: AppShape.cardBorder,
                        isExpanded: true,
                        value: page?.number,
                        hint: const Text('选择页码'),
                        items: document.pages
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.number,
                                child: Text(
                                  '第 ${p.number} / ${document.pageCount} 页',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (number) {
                          if (number != null) _select(document.assetId, number);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: '下一页',
                      onPressed:
                          page != null && _pageNumber < document.pageCount
                          ? () => _select(document.assetId, _pageNumber + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                if (page != null && !invalidTarget)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: page.text.trim().isEmpty
                        ? const Text('本页没有文本，可切换到原页查看。')
                        : SelectableText(
                            page.text,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(height: 1.6),
                          ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _statusLabel(DocumentText document) => switch (document.status) {
    'partial' => '${document.textPageCount} / ${document.pageCount} 页有文本',
    'no_text' => '没有可读取的文本，可切换到原页查看。',
    'pending' => '正文尚未提取',
    'encrypted' => '文件已加密，无法读取正文。请上传解密后的 PDF。',
    'invalid_pdf' => '文件损坏或不是有效 PDF，原文件仍保留。',
    'limit_exceeded' => '文件超过提取上限（64 MiB、500 页或 200 万字），原文件仍可打开。',
    'timeout' => '提取超过 60 秒，已停止。可查看原文件或重试。',
    'missing' => '归档原文件不可读取。',
    'source_changed' => '原文件已变化，请重新提取。',
    _ => '正文提取失败，可重试或查看原文件。',
  };
}
