import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key});

  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AgentMessage> _messages = [];
  final String _sessionId = 'web-${DateTime.now().millisecondsSinceEpoch}';
  bool _isSending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendPrompt([String? preset]) async {
    if (_isSending) return;
    final prompt = (preset ?? _inputController.text).trim();
    if (prompt.isEmpty) return;

    _inputController.clear();
    setState(() {
      _messages.add(_AgentMessage.user(prompt));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final dio = ref.read(apiClientProvider);
      final response = await dio.post(
        '/agent/run',
        data: {
          'message': prompt,
          'session_id': _sessionId,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final data = response.data as Map<String, dynamic>? ?? {};
      final tool = (data['tool'] as String?) ?? 'unknown';
      final result = data['result'] as Map<String, dynamic>? ?? {};
      final content = _formatAgentOutput(tool: tool, result: result);

      setState(() {
        _messages.add(_AgentMessage.assistant(content, tool: tool));
      });
    } on DioException catch (e) {
      setState(() {
        _messages.add(
          _AgentMessage.error(
            formatApiErrorMessage(
              e,
              fallbackMessage: 'Agent 请求失败，请稍后重试',
            ),
          ),
        );
      });
    } catch (_) {
      setState(() {
        _messages.add(_AgentMessage.error('Agent 请求失败，请稍后重试'));
      });
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToBottom();
      }
    }
  }

  String _formatAgentOutput({
    required String tool,
    required Map<String, dynamic> result,
  }) {
    if (tool == 'search_content') {
      final items = (result['items'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (items.isEmpty) return '未找到相关内容。';
      final lines = <String>['共 ${items.length} 条结果:'];
      for (final item in items.take(6)) {
        final title = (item['title'] as String?)?.trim();
        final url = (item['url'] as String?)?.trim();
        final contentId = item['content_id'];
        lines.add('- [${contentId ?? "-"}] ${title?.isNotEmpty == true ? title : url ?? "无标题"}');
      }
      return lines.join('\n');
    }

    if (tool == 'list_groups') {
      final groups = (result['groups'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (groups.isEmpty) return '当前没有可用群组。';
      final lines = <String>['可用群组 ${groups.length} 个:'];
      for (final group in groups.take(8)) {
        lines.add('- ${group['title'] ?? group['chat_id']} (${group['chat_id']})');
      }
      return lines.join('\n');
    }

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(result);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent'),
        actions: [
          IconButton(
            tooltip: '清空会话',
            onPressed: _messages.isEmpty
                ? null
                : () {
                    setState(_messages.clear);
                  },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _MessageBubble(message: message);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendPrompt(),
                      decoration: const InputDecoration(
                        hintText: '输入自然语言指令，例如：同步知乎收藏',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSending ? null : _sendPrompt,
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_outlined,
                size: 46,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Agent 面板',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '可用示例: “列出可用群组” / “同步知乎收藏” / “搜索 Rust 异步内容”',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(
                    label: const Text('列出群组'),
                    onPressed: () => _sendPrompt('列出可用群组'),
                  ),
                  ActionChip(
                    label: const Text('同步知乎收藏'),
                    onPressed: () => _sendPrompt('同步知乎收藏'),
                  ),
                  ActionChip(
                    label: const Text('搜索 Rust'),
                    onPressed: () => _sendPrompt('Rust 异步运行时'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _AgentMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == _MessageRole.user;
    final isError = message.role == _MessageRole.error;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;

    Color bgColor;
    Color fgColor;
    if (isUser) {
      bgColor = theme.colorScheme.primaryContainer;
      fgColor = theme.colorScheme.onPrimaryContainer;
    } else if (isError) {
      bgColor = theme.colorScheme.errorContainer;
      fgColor = theme.colorScheme.onErrorContainer;
    } else {
      bgColor = theme.colorScheme.surfaceContainerHighest;
      fgColor = theme.colorScheme.onSurfaceVariant;
    }

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.tool != null && message.tool!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '[${message.tool}]',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: fgColor.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              SelectableText(
                message.content,
                style: theme.textTheme.bodyMedium?.copyWith(color: fgColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MessageRole { user, assistant, error }

class _AgentMessage {
  const _AgentMessage({
    required this.role,
    required this.content,
    this.tool,
  });

  factory _AgentMessage.user(String content) =>
      _AgentMessage(role: _MessageRole.user, content: content);

  factory _AgentMessage.assistant(String content, {String? tool}) =>
      _AgentMessage(role: _MessageRole.assistant, content: content, tool: tool);

  factory _AgentMessage.error(String content) =>
      _AgentMessage(role: _MessageRole.error, content: content);

  final _MessageRole role;
  final String content;
  final String? tool;
}
