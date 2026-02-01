import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../../models/content.dart';
import '../../providers/collection_provider.dart';

class EditContentDialog extends ConsumerStatefulWidget {
  final ContentDetail content;

  const EditContentDialog({super.key, required this.content});

  @override
  ConsumerState<EditContentDialog> createState() => _EditContentDialogState();
}

class _EditContentDialogState extends ConsumerState<EditContentDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _authorController;
  late TextEditingController _tagsController;
  late TextEditingController _coverUrlController;
  late bool _isNsfw;
  String? _selectedLayout;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.content.title);
    _descriptionController = TextEditingController(
      text: widget.content.description,
    );
    _authorController = TextEditingController(text: widget.content.authorName);
    _tagsController = TextEditingController(
      text: widget.content.tags.join(' '),
    );
    _coverUrlController = TextEditingController(text: widget.content.coverUrl);
    _isNsfw = widget.content.isNsfw;
    _selectedLayout = widget.content.layoutTypeOverride;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _tagsController.dispose();
    _coverUrlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(apiClientProvider);
      final tags = _tagsController.text
          .split(RegExp(r'[,\s，]'))
          .where((t) => t.isNotEmpty)
          .toList();

      await dio.patch(
        '/contents/${widget.content.id}',
        data: {
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'author_name': _authorController.text.trim(),
          'cover_url': _coverUrlController.text.trim(),
          'tags': tags,
          'is_nsfw': _isNsfw,
          'layout_type_override': _selectedLayout,
        },
      );

      if (mounted) {
        // 刷新详情和列表
        ref.invalidate(contentDetailProvider(widget.content.id));
        ref.invalidate(collectionProvider);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '修改失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('编辑内容'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _authorController,
              decoration: const InputDecoration(
                labelText: '作者',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _coverUrlController,
              decoration: const InputDecoration(
                labelText: '封面图 URL',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '显示样式',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _selectedLayout,
                  isDense: true,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('自动检测 (默认)')),
                    DropdownMenuItem(value: 'article', child: Text('文章 (Article)')),
                    DropdownMenuItem(value: 'gallery', child: Text('画廊 (Gallery)')),
                    DropdownMenuItem(value: 'video', child: Text('视频 (Video)')),
                  ],
                  onChanged: _isLoading ? null : (val) => setState(() => _selectedLayout = val),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: '标签',
                hintText: '使用空格或逗号分隔',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('标记为 NSFW'),
              value: _isNsfw,
              onChanged: _isLoading
                  ? null
                  : (val) => setState(() => _isNsfw = val),
              contentPadding: EdgeInsets.zero,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
