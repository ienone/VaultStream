import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/network/api_client.dart';
import '../../core/providers/local_settings_provider.dart';
import 'models/agent_result.dart';

class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key});

  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<AgentSessionSummary> _sessions = const [];
  final List<_TimelineItem> _timeline = [];
  String? _sessionId;
  String? _activeRunId;
  String _assistantDraft = '';
  bool _loading = true;
  bool _streaming = false;
  bool _stopRequested = false;
  String? _error;
  http.Client? _streamClient;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _streamClient?.close();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      await _loadSessions();
      if (_sessions.isEmpty) {
        await _createSession();
      } else {
        await _selectSession(_sessions.first.id);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSessions() async {
    final dio = ref.read(apiClientProvider);
    final resp = await dio.get('/agent/sessions');
    final data = resp.data as Map<String, dynamic>? ?? {};
    final sessions = (data['sessions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AgentSessionSummary.fromJson)
        .toList();
    if (mounted) setState(() => _sessions = sessions);
  }

  Future<void> _createSession() async {
    final dio = ref.read(apiClientProvider);
    final resp = await dio.post('/agent/sessions', data: {'title': '新会话'});
    final session = AgentSessionSummary.fromJson(
      resp.data as Map<String, dynamic>,
    );
    if (mounted) {
      setState(() {
        _sessions = [session, ..._sessions];
        _sessionId = session.id;
        _timeline.clear();
      });
    }
  }

  Future<void> _selectSession(String sessionId) async {
    final dio = ref.read(apiClientProvider);
    final resp = await dio.get('/agent/sessions/$sessionId/messages');
    final data = resp.data as Map<String, dynamic>? ?? {};
    final messages = (data['messages'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AgentMessageRecord.fromJson)
        .map(_TimelineItem.fromMessage)
        .toList();
    if (mounted) {
      setState(() {
        _sessionId = sessionId;
        _timeline
          ..clear()
          ..addAll(messages);
        _assistantDraft = '';
        _error = null;
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendPrompt([String? preset]) async {
    if (_streaming) return;
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty) return;
    if (_sessionId == null) await _createSession();

    _inputController.clear();
    setState(() {
      _streaming = true;
      _stopRequested = false;
      _error = null;
      _assistantDraft = '';
      _timeline.add(_TimelineItem.user(text));
      _timeline.add(_TimelineItem.assistantDraft());
    });
    _scrollToBottom();

    final local = ref.read(localSettingsProvider);
    final uri = Uri.parse(local.baseUrl).replace(
      path: '${Uri.parse(local.baseUrl).path}/agent/sse',
      queryParameters: {
        'message': text,
        if (_sessionId != null) 'session_id': _sessionId!,
      },
    );

    final client = http.Client();
    _streamClient = client;
    try {
      final request = http.Request('GET', uri)
        ..headers['X-API-Token'] = local.apiToken;
      final response = await client.send(request);
      if (response.statusCode >= 400) {
        throw StateError('Agent stream failed: HTTP ${response.statusCode}');
      }
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final raw = line.substring(5).trim();
        if (raw.isEmpty) continue;
        final event = jsonDecode(raw);
        if (event is Map<String, dynamic>) {
          _applyEvent(event);
        }
      }
    } catch (e) {
      if (mounted && !_stopRequested) {
        setState(() {
          _error = 'Agent 流式请求失败: $e';
          _replaceDraft(_TimelineItem.error(_error!));
        });
      }
    } finally {
      client.close();
      if (identical(_streamClient, client)) _streamClient = null;
      if (mounted) {
        setState(() => _streaming = false);
        _stopRequested = false;
        unawaited(_loadSessions());
        _scrollToBottom();
      }
    }
  }

  void _applyEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    setState(() {
      final type = event['type']?.toString() ?? 'message';
      switch (type) {
        case 'start':
          _sessionId = event['session_id']?.toString() ?? _sessionId;
          _activeRunId = event['run_id']?.toString();
          break;
        case 'assistant_delta':
          _assistantDraft += event['content']?.toString() ?? '';
          _replaceDraft(_TimelineItem.assistant(_assistantDraft));
          break;
        case 'tool_call':
          _timeline.add(_TimelineItem.toolCall(event));
          break;
        case 'tool_result':
          _timeline.add(_TimelineItem.toolResult(event));
          break;
        case 'confirmation_required':
          final raw = event['confirmation'];
          if (raw is Map<String, dynamic>) {
            _timeline.add(
              _TimelineItem.confirmation(AgentConfirmation.fromJson(raw)),
            );
          }
          break;
        case 'context_summary':
          _timeline.add(_TimelineItem.notice('已压缩较早上下文，保留可追踪摘要。'));
          break;
        case 'usage':
          _timeline.add(
            _TimelineItem.notice('用量: ${prettyJson(event['usage'])}'),
          );
          break;
        case 'error':
          _replaceDraft(_TimelineItem.error(_formatEventError(event)));
          break;
        case 'final':
          final message = event['message']?.toString();
          if (message != null && message.trim().isNotEmpty) {
            _replaceDraft(_TimelineItem.assistant(message));
          }
          break;
        default:
          _timeline.add(_TimelineItem.notice(prettyJson(event)));
      }
    });
    _scrollToBottom();
  }

  Future<void> _decideConfirmation(
    AgentConfirmation confirmation,
    bool approved,
  ) async {
    final dio = ref.read(apiClientProvider);
    try {
      final resp = await dio.post(
        '/agent/confirmations/${confirmation.id}/decide',
        data: {'approved': approved},
      );
      final result = AgentRunResponse.fromJson(
        resp.data as Map<String, dynamic>,
      );
      for (final event in result.events) {
        _applyEvent(event);
      }
      await _loadSessions();
    } on DioException catch (e) {
      setState(
        () => _timeline.add(_TimelineItem.error(_formatAgentErrorMessage(e))),
      );
    }
  }

  Future<void> _redo() async {
    if (_sessionId == null || _streaming) return;
    final dio = ref.read(apiClientProvider);
    try {
      final resp = await dio.post('/agent/sessions/$_sessionId/redo');
      final result = AgentRunResponse.fromJson(
        resp.data as Map<String, dynamic>,
      );
      for (final event in result.events) {
        _applyEvent(event);
      }
    } on DioException catch (e) {
      setState(
        () => _timeline.add(_TimelineItem.error(_formatAgentErrorMessage(e))),
      );
    }
  }

  Future<void> _stop() async {
    _stopRequested = true;
    _streamClient?.close();
    final runId = _activeRunId;
    if (runId == null) {
      if (mounted) setState(() => _streaming = false);
      return;
    }
    final dio = ref.read(apiClientProvider);
    await dio.post('/agent/runs/$runId/stop');
    if (mounted) {
      setState(() {
        _streaming = false;
        _timeline.add(_TimelineItem.notice('已请求停止当前 run。'));
      });
    }
  }

  Future<void> _clearSession() async {
    if (_sessionId == null) return;
    final dio = ref.read(apiClientProvider);
    await dio.post('/agent/sessions/$_sessionId/clear');
    if (mounted) setState(_timeline.clear);
  }

  void _replaceDraft(_TimelineItem item) {
    final index = _timeline.lastIndexWhere(
      (it) => it.kind == _TimelineKind.assistantDraft,
    );
    if (index >= 0) {
      _timeline[index] = item;
    } else if (item.kind == _TimelineKind.assistant ||
        item.kind == _TimelineKind.error) {
      _timeline.add(item);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _formatEventError(Map<String, dynamic> event) {
    final code = event['error_code']?.toString() ?? 'agent_error';
    final msg = event['message']?.toString() ?? 'Agent 执行失败';
    final fix = event['suggested_fix']?.toString();
    return fix == null || fix.isEmpty ? '$code: $msg' : '$code: $msg\n$fix';
  }

  String _formatAgentErrorMessage(DioException error) {
    final info = parseApiErrorInfo(error, fallbackMessage: 'Agent 请求失败，请稍后重试');
    final message = switch (info.code) {
      'agent_model_unavailable' => '模型配置不可用。请检查文本模型配置后重试。',
      'agent_invalid_message' => '没有识别到可执行指令。请补充目标或关键词。',
      'agent_tool_not_found' => '当前工具不可用。请刷新工具列表后重试。',
      'agent_tool_invalid_args' => '参数不完整或格式不正确。请补充目标、关键词或群组信息。',
      'agent_confirmation_not_found' => '确认请求已失效。请重新发起操作。',
      'agent_tool_execution_failed' => '工具执行失败。请检查相关配置或稍后重试。',
      'agent_execution_failed' => 'Agent 执行失败。请改成更具体的单步指令后重试。',
      _ => formatApiErrorMessage(error, fallbackMessage: 'Agent 请求失败，请稍后重试'),
    };
    if (info.requestId == null || info.requestId!.isEmpty) return message;
    final shortId = info.requestId!.length > 8
        ? info.requestId!.substring(0, 8)
        : info.requestId!;
    return '$message | RID:$shortId';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 920;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent 工作台'),
        actions: [
          IconButton(
            tooltip: '重做上一步',
            onPressed: _streaming ? null : _redo,
            icon: const Icon(Icons.replay_rounded),
          ),
          IconButton(
            tooltip: _streaming ? '停止' : '刷新',
            onPressed: _streaming ? _stop : _bootstrap,
            icon: Icon(_streaming ? Icons.stop_rounded : Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: '清空当前会话',
            onPressed: _timeline.isEmpty ? null : _clearSession,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wide
          ? Row(
              children: [
                SizedBox(width: 300, child: _SessionPane(state: this)),
                const VerticalDivider(width: 1),
                Expanded(child: _ConversationPane(state: this)),
              ],
            )
          : Column(
              children: [
                SizedBox(height: 92, child: _CompactSessionBar(state: this)),
                const Divider(height: 1),
                Expanded(child: _ConversationPane(state: this)),
              ],
            ),
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({required this.state});

  final _AgentPageState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: state._timeline.isEmpty
              ? _EmptyWorkbench(onPrompt: state._sendPrompt)
              : ListView.builder(
                  controller: state._scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: state._timeline.length,
                  itemBuilder: (context, index) => _TimelineTile(
                    item: state._timeline[index],
                    onDecide: state._decideConfirmation,
                  ),
                ),
        ),
        if (state._error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _InlineError(message: state._error!),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: state._inputController,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => state._sendPrompt(),
                    decoration: const InputDecoration(
                      hintText: '询问内容库、创建规则、同步收藏或批量推送',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: state._streaming ? state._stop : state._sendPrompt,
                  icon: Icon(
                    state._streaming ? Icons.stop_rounded : Icons.send_rounded,
                  ),
                  label: Text(state._streaming ? '停止' : '发送'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionPane extends StatelessWidget {
  const _SessionPane({required this.state});

  final _AgentPageState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: state._createSession,
            icon: const Icon(Icons.add_rounded),
            label: const Text('新会话'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: state._sessions.length,
            itemBuilder: (context, index) {
              final session = state._sessions[index];
              return _SessionTile(
                session: session,
                selected: session.id == state._sessionId,
                onTap: () => state._selectSession(session.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactSessionBar extends StatelessWidget {
  const _CompactSessionBar({required this.state});

  final _AgentPageState state;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      scrollDirection: Axis.horizontal,
      itemCount: state._sessions.length + 1,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return ActionChip(
            avatar: const Icon(Icons.add_rounded),
            label: const Text('新会话'),
            onPressed: state._createSession,
          );
        }
        final session = state._sessions[index - 1];
        return ChoiceChip(
          selected: session.id == state._sessionId,
          label: Text(session.title, overflow: TextOverflow.ellipsis),
          onSelected: (_) => state._selectSession(session.id),
        );
      },
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final AgentSessionSummary session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      leading: Icon(
        session.pendingConfirmations > 0
            ? Icons.verified_user_outlined
            : Icons.forum_outlined,
      ),
      title: Text(session.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        session.pendingConfirmations > 0
            ? '${session.pendingConfirmations} 个待确认'
            : session.status,
        maxLines: 1,
      ),
      selectedTileColor: theme.colorScheme.secondaryContainer.withValues(
        alpha: 0.5,
      ),
      onTap: onTap,
    );
  }
}

class _EmptyWorkbench extends StatelessWidget {
  const _EmptyWorkbench({required this.onPrompt});

  final Future<void> Function(String prompt) onPrompt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.hub_outlined,
                size: 42,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.search_rounded),
                    label: const Text('检索最近的 AI Agent 内容'),
                    onPressed: () =>
                        onPrompt('检索内容库中关于 AI Agent 安全风险的资料，并引用来源'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.groups_rounded),
                    label: const Text('列出推送群组'),
                    onPressed: () => onPrompt('列出当前可用推送群组'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.rule_rounded),
                    label: const Text('创建规则'),
                    onPressed: () => onPrompt('为 #AI 标签创建一条需要审批的自动推送规则'),
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

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.item, required this.onDecide});

  final _TimelineItem item;
  final Future<void> Function(AgentConfirmation confirmation, bool approved)
  onDecide;

  @override
  Widget build(BuildContext context) {
    return switch (item.kind) {
      _TimelineKind.user => _Bubble(
        icon: Icons.person_outline_rounded,
        alignRight: true,
        child: SelectableText(item.text),
      ),
      _TimelineKind.assistant || _TimelineKind.assistantDraft => _Bubble(
        icon: Icons.smart_toy_outlined,
        child: item.kind == _TimelineKind.assistantDraft
            ? const LinearProgressIndicator(minHeight: 3)
            : SelectableText(item.text),
      ),
      _TimelineKind.toolCall => _ToolEvent(event: item.event!, running: true),
      _TimelineKind.toolResult => _ToolEvent(
        event: item.event!,
        running: false,
      ),
      _TimelineKind.confirmation => _ConfirmationTile(
        confirmation: item.confirmation!,
        onDecide: onDecide,
      ),
      _TimelineKind.notice => _Notice(text: item.text),
      _TimelineKind.error => _InlineError(message: item.text),
    };
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.child,
    required this.icon,
    this.alignRight = false,
  });

  final Widget child;
  final IconData icon;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = alignRight
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 820),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _ToolEvent extends StatelessWidget {
  const _ToolEvent({required this.event, required this.running});

  final Map<String, dynamic> event;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final citations = citationsFromToolResult(event);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                running
                    ? Icons.build_circle_outlined
                    : Icons.check_circle_outline_rounded,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${event['tool'] ?? 'tool'} ${running ? '调用中' : '结果'}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (citations.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: citations
                  .take(5)
                  .map((c) => _CitationChip(citation: c))
                  .toList(),
            ),
          ] else ...[
            const SizedBox(height: 8),
            SelectableText(
              prettyJson(
                running ? event['args'] : event['result'] ?? event['error'],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _CitationChip extends StatelessWidget {
  const _CitationChip({required this.citation});

  final AgentCitation citation;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: const Icon(Icons.article_outlined, size: 18),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Text(
          '#${citation.contentId} ${citation.title}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      tooltip:
          '${citation.matchSource} ${citation.chunkTitle ?? ''}\n${citation.sourceText ?? citation.url}',
      onPressed: () {},
    );
  }
}

class _ConfirmationTile extends StatelessWidget {
  const _ConfirmationTile({required this.confirmation, required this.onDecide});

  final AgentConfirmation confirmation;
  final Future<void> Function(AgentConfirmation confirmation, bool approved)
  onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${confirmation.toolName} 需要确认',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(confirmation.summary),
          const SizedBox(height: 8),
          SelectableText(
            prettyJson(confirmation.args),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => onDecide(confirmation, true),
                icon: const Icon(Icons.check_rounded),
                label: const Text('确认'),
              ),
              OutlinedButton.icon(
                onPressed: () => onDecide(confirmation, false),
                icon: const Icon(Icons.close_rounded),
                label: const Text('拒绝'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

enum _TimelineKind {
  user,
  assistant,
  assistantDraft,
  toolCall,
  toolResult,
  confirmation,
  notice,
  error,
}

class _TimelineItem {
  const _TimelineItem({
    required this.kind,
    this.text = '',
    this.event,
    this.confirmation,
  });

  factory _TimelineItem.fromMessage(AgentMessageRecord message) {
    return switch (message.role) {
      'user' => _TimelineItem.user(message.content),
      'tool' => _TimelineItem.notice(message.content),
      'assistant' => _TimelineItem.assistant(message.content),
      _ => _TimelineItem.notice(message.content),
    };
  }

  factory _TimelineItem.user(String text) =>
      _TimelineItem(kind: _TimelineKind.user, text: text);

  factory _TimelineItem.assistant(String text) =>
      _TimelineItem(kind: _TimelineKind.assistant, text: text);

  factory _TimelineItem.assistantDraft() =>
      const _TimelineItem(kind: _TimelineKind.assistantDraft);

  factory _TimelineItem.toolCall(Map<String, dynamic> event) =>
      _TimelineItem(kind: _TimelineKind.toolCall, event: event);

  factory _TimelineItem.toolResult(Map<String, dynamic> event) =>
      _TimelineItem(kind: _TimelineKind.toolResult, event: event);

  factory _TimelineItem.confirmation(AgentConfirmation confirmation) =>
      _TimelineItem(
        kind: _TimelineKind.confirmation,
        confirmation: confirmation,
      );

  factory _TimelineItem.notice(String text) =>
      _TimelineItem(kind: _TimelineKind.notice, text: text);

  factory _TimelineItem.error(String text) =>
      _TimelineItem(kind: _TimelineKind.error, text: text);

  final _TimelineKind kind;
  final String text;
  final Map<String, dynamic>? event;
  final AgentConfirmation? confirmation;
}
