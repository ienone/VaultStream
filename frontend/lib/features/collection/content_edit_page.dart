import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/content.dart';
import '../../core/network/api_client.dart';
import 'providers/content_editor_key_provider.dart';
import 'widgets/content_editor.dart';

final _editContentProvider = FutureProvider.autoDispose
    .family<ContentDetail, int>((ref, id) async {
      final response = await ref
          .watch(apiClientProvider)
          .get('/contents/$id', queryParameters: {'for_edit': true});
      return ContentDetail.fromJson(response.data);
    });

class ContentEditPage extends ConsumerStatefulWidget {
  const ContentEditPage({
    super.key,
    required this.contentId,
    required this.routeKey,
  });
  final int contentId;
  final ValueKey<String> routeKey;

  @override
  ConsumerState<ContentEditPage> createState() => _ContentEditPageState();
}

class _ContentEditPageState extends ConsumerState<ContentEditPage> {
  ContentDetail? _initialContent;

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(_editContentProvider(widget.contentId));
    // Background refreshes must not replace the original revision or draft.
    _initialContent ??= content.value;
    final detail = _initialContent;
    if (detail != null) {
      return ContentEditor(
        key: ref.watch(
          contentEditorKeyProvider((widget.routeKey, widget.contentId)),
        ),
        content: detail,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑内容'),
        leading: IconButton(
          tooltip: '返回',
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: content.when(
          data: (_) => const SizedBox.shrink(),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('无法加载要编辑的内容'),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(_editContentProvider(widget.contentId)),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
