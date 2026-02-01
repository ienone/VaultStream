import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../collection/providers/collection_provider.dart';
import 'share_receiver_service.dart';

/// 分享提交底部弹窗
/// 用户从其他 App 分享内容到 VaultStream 时显示
class ShareSubmitSheet extends ConsumerStatefulWidget {
  final SharedContent sharedContent;
  final VoidCallback? onSubmitted;
  final VoidCallback? onCancelled;

  const ShareSubmitSheet({
    super.key,
    required this.sharedContent,
    this.onSubmitted,
    this.onCancelled,
  });

  /// 显示分享提交弹窗
  static Future<bool?> show(
    BuildContext context,
    SharedContent content, {
    VoidCallback? onSubmitted,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ShareSubmitSheet(
        sharedContent: content,
        onSubmitted: onSubmitted,
      ),
    );
  }

  @override
  ConsumerState<ShareSubmitSheet> createState() => _ShareSubmitSheetState();
}

class _ShareSubmitSheetState extends ConsumerState<ShareSubmitSheet> {
  final _tagsController = TextEditingController();
  final _selectedTags = <String>{};
  String? _selectedLayout;
  bool _isNsfw = false;
  bool _isLoading = false;
  String? _errorMessage;

  // 常用标签 - 可以从后端获取或本地配置
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

  String? get _url => widget.sharedContent.extractedUrl;
  String? get _rawText => widget.sharedContent.text;

  @override
  void dispose() {
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _url;
    if (url == null) {
      setState(() => _errorMessage = '未检测到有效的 URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ref.read(apiClientProvider);

      // 合并快捷标签和手动输入的标签
      final manualTags = _tagsController.text
          .split(RegExp(r'[,\s，]'))
          .where((t) => t.isNotEmpty)
          .toList();
      final allTags = {..._selectedTags, ...manualTags}.toList();

      await dio.post(
        '/shares',
        data: {
          'url': url,
          'tags': allTags,
          'is_nsfw': _isNsfw,
          'source': 'android_share',
          'layout_type_override': _selectedLayout,
        },
      );

      if (mounted) {
        // 刷新收藏列表
        ref.invalidate(collectionProvider);

        // 清除分享内容
        ref.read(shareReceiverServiceProvider).clearSharedContent();

        widget.onSubmitted?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = '提交失败: $e';
      });
    }
  }

  void _cancel() {
    ref.read(shareReceiverServiceProvider).clearSharedContent();
    widget.onCancelled?.call();
    Navigator.of(context).pop(false);
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
                  '保存到 VaultStream',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // URL 预览
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _url ?? _rawText ?? '无内容',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _url != null
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 布局选择
            InputDecorator(
              decoration: const InputDecoration(
                labelText: '显示样式',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.view_quilt_outlined),
                isDense: true,
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
              onChanged: _isLoading ? null : (val) => setState(() => _isNsfw = val),
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
                    Icon(Icons.error_outline, color: colorScheme.error, size: 20),
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
                    onPressed: _isLoading ? null : _cancel,
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _isLoading || _url == null ? null : _submit,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isLoading ? '保存中...' : '保存'),
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
