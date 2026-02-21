import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/content.dart';

class PayloadBlockRenderer extends StatelessWidget {
  final ContentDetail content;

  const PayloadBlockRenderer({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final payload = content.richPayload;
    if (payload == null) return const SizedBox.shrink();

    final blocks = payload['blocks'] as List<dynamic>?;
    if (blocks == null || blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map<Widget>((block) {
        if (block is! Map<String, dynamic>) return const SizedBox.shrink();
        final type = block['type'] as String?;
        final data = block['data'] as Map<String, dynamic>?;

        if (type == 'sub_item' && data != null) {
            return _buildSubItem(context, data);
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  Widget _buildSubItem(BuildContext context, Map<String, dynamic> data) {
      final title = data['title'] as String?;
      final excerpt = data['excerpt'] as String?;
      final url = data['url'] as String?;
      
      return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          child: InkWell(
            onTap: url != null ? () => launchUrl(Uri.parse(url)) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                if (title != null)
                                    Text(
                                        title, 
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis
                                    ),
                                if (excerpt != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                          excerpt, 
                                          style: Theme.of(context).textTheme.bodySmall,
                                          maxLines: 2, 
                                          overflow: TextOverflow.ellipsis
                                      ),
                                    ),
                            ],
                        ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
                ],
              ),
            ),
          ),
      );
  }
}
