import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/sse_service.dart';

class DocumentTextPage {
  const DocumentTextPage({required this.number, required this.text});
  final int number;
  final String text;
}

class DocumentText {
  DocumentText.fromJson(Map<String, dynamic> json)
    : assetId = json['media_asset_id'] as int,
      filename = json['filename'] as String,
      status = json['status'] as String,
      pageCount = json['page_count'] as int,
      textPageCount = json['text_page_count'] as int,
      pages = (json['pages'] as List)
          .map((raw) {
            final page = raw as Map<String, dynamic>;
            return DocumentTextPage(
              number: page['page_number'] as int,
              text: page['text'] as String,
            );
          })
          .toList(growable: false);

  final int assetId;
  final String filename;
  final String status;
  final int pageCount;
  final int textPageCount;
  final List<DocumentTextPage> pages;
}

final documentTextProvider = FutureProvider.autoDispose
    .family<List<DocumentText>, int>((ref, contentId) async {
      refreshOnEvents(ref, (event) => affectsContent(event, contentId));
      final response = await ref
          .watch(apiClientProvider)
          .get<Map<String, dynamic>>('/contents/$contentId/document-text');
      return (response.data!['documents'] as List)
          .map((raw) => DocumentText.fromJson(raw as Map<String, dynamic>))
          .toList(growable: false);
    });
