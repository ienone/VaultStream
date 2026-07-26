import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/content_actions_controller.dart';

class AddContentDialog extends ConsumerStatefulWidget {
  const AddContentDialog({super.key});

  /// 显示添加内容底部弹窗
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddContentDialog(),
    );
  }

  @override
  ConsumerState<AddContentDialog> createState() => _AddContentDialogState();
}

class _AddContentDialogState extends ConsumerState<AddContentDialog> {
  final _urlController = TextEditingController();
  final _tagsController = TextEditingController();
  final _selectedTags = <String>{};
  bool _isNsfw = false;
  bool _isLoading = false;
  String? _errorMessage;

  static const List<String> _quickTags = [
    '待看',
    '收藏',
    '学习',
    '工作',
    '灵感',
    '有趣',
    '技术',
    '设计',
  ];

  @override
  void dispose() {
    _urlController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = '请输入有效的 URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 合并快捷标签和自定义标签。
    final customTags = _tagsController.text
        .split(RegExp(r'[,\s，]'))
        .where((t) => t.isNotEmpty)
        .toList();
    final allTags = {..._selectedTags, ...customTags}.toList();
    final result = await ref
        .read(contentActionsProvider.notifier)
        .createShare(url: url, tags: allTags, isNsfw: _isNsfw);

    if (!mounted) return;
    if (result.ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖动指示器
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 标题
            Row(
              children: [
                Icon(Icons.add_link, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  '添加收藏内容',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // URL 输入
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'URL',
                hintText: 'https://...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
                isDense: true,
              ),
              autofocus: true,
              enabled: !_isLoading,
            ),
            const SizedBox(height: 20),

            // 快捷标签
            Text(
              '快捷标签',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickTags.map((tag) {
                final isSelected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag),
                  selected: isSelected,
                  onSelected: _isLoading
                      ? null
                      : (selected) {
                          setState(() {
                            if (selected) {
                              _selectedTags.add(tag);
                            } else {
                              _selectedTags.remove(tag);
                            }
                          });
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // 自定义标签输入
            TextField(
              controller: _tagsController,
              decoration: InputDecoration(
                labelText: '自定义标签',
                hintText: '用空格或逗号分隔',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.label_outline),
                isDense: true,
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 12),

            // NSFW 开关
            SwitchListTile(
              title: const Text('标记为 NSFW'),
              subtitle: Text(
                '敏感内容将被隐藏',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: _isNsfw,
              onChanged: _isLoading
                  ? null
                  : (val) => setState(() => _isNsfw = val),
              contentPadding: EdgeInsets.zero,
            ),

            // 错误信息
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('提交'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
