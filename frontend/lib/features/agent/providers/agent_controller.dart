import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers/local_settings_provider.dart';
import '../models/agent_result.dart';

part 'agent_controller.freezed.dart';

enum AgentStreamEventType {
  start,
  assistantDelta,
  toolCall,
  toolResult,
  confirmationRequired,
  contextSummary,
  usage,
  error,
  finalResult,
  unknown,
}

@immutable
class AgentStreamEvent {
  const AgentStreamEvent({required this.type, required this.payload});

  factory AgentStreamEvent.fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']?.toString()) {
      'start' => AgentStreamEventType.start,
      'assistant_delta' => AgentStreamEventType.assistantDelta,
      'tool_call' => AgentStreamEventType.toolCall,
      'tool_result' => AgentStreamEventType.toolResult,
      'confirmation_required' => AgentStreamEventType.confirmationRequired,
      'context_summary' => AgentStreamEventType.contextSummary,
      'usage' => AgentStreamEventType.usage,
      'error' => AgentStreamEventType.error,
      'final' => AgentStreamEventType.finalResult,
      _ => AgentStreamEventType.unknown,
    };
    return AgentStreamEvent(type: type, payload: Map.unmodifiable(json));
  }

  final AgentStreamEventType type;
  final Map<String, dynamic> payload;

  String? get sessionId => payload['session_id']?.toString();
  String? get runId => payload['run_id']?.toString();
  String get content => payload['content']?.toString() ?? '';
  String? get message => payload['message']?.toString();

  AgentConfirmation? get confirmation {
    final raw = payload['confirmation'];
    return raw is Map<String, dynamic> ? AgentConfirmation.fromJson(raw) : null;
  }
}

enum AgentTimelineKind {
  user,
  assistant,
  assistantDraft,
  toolCall,
  toolResult,
  confirmation,
  notice,
  error,
}

@immutable
class AgentTimelineItem {
  const AgentTimelineItem({
    required this.kind,
    this.text = '',
    this.event,
    this.confirmation,
    this.details,
  });

  factory AgentTimelineItem.fromMessage(AgentMessageRecord message) {
    return switch (message.role) {
      'user' => AgentTimelineItem.user(message.content),
      'tool' => AgentTimelineItem.toolResult(_storedToolEvent(message)),
      'assistant' => AgentTimelineItem.assistant(message.content),
      _ => AgentTimelineItem.notice(message.content),
    };
  }

  factory AgentTimelineItem.user(String text) =>
      AgentTimelineItem(kind: AgentTimelineKind.user, text: text);

  factory AgentTimelineItem.assistant(String text) =>
      AgentTimelineItem(kind: AgentTimelineKind.assistant, text: text);

  factory AgentTimelineItem.assistantDraft() =>
      const AgentTimelineItem(kind: AgentTimelineKind.assistantDraft);

  factory AgentTimelineItem.toolCall(Map<String, dynamic> event) =>
      AgentTimelineItem(kind: AgentTimelineKind.toolCall, event: event);

  factory AgentTimelineItem.toolResult(Map<String, dynamic> event) =>
      AgentTimelineItem(kind: AgentTimelineKind.toolResult, event: event);

  factory AgentTimelineItem.confirmation(AgentConfirmation confirmation) =>
      AgentTimelineItem(
        kind: AgentTimelineKind.confirmation,
        confirmation: confirmation,
      );

  factory AgentTimelineItem.notice(String text, {String? details}) =>
      AgentTimelineItem(
        kind: AgentTimelineKind.notice,
        text: text,
        details: details,
      );

  factory AgentTimelineItem.error(String text) =>
      AgentTimelineItem(kind: AgentTimelineKind.error, text: text);

  final AgentTimelineKind kind;
  final String text;
  final Map<String, dynamic>? event;
  final AgentConfirmation? confirmation;
  final String? details;
}

Map<String, dynamic> _storedToolEvent(AgentMessageRecord message) {
  return {
    'type': 'tool_result',
    'tool': message.payload['tool'] ?? 'tool',
    ...message.payload,
  };
}

@freezed
abstract class AgentViewState with _$AgentViewState {
  const factory AgentViewState({
    @Default([]) List<AgentSessionSummary> sessions,
    @Default([]) List<AgentTimelineItem> timeline,
    @Default({}) Set<String> decidingConfirmationIds,
    String? sessionId,
    String? activeRunId,
    @Default(true) bool loading,
    @Default(false) bool streaming,
    String? error,
  }) = _AgentViewState;
}

final agentControllerProvider = NotifierProvider.family
    .autoDispose<AgentController, AgentViewState, String?>(AgentController.new);

final agentStreamClientFactoryProvider = Provider<http.Client Function()>(
  (ref) => http.Client.new,
);

class AgentController extends Notifier<AgentViewState> {
  AgentController(this.initialSessionId);

  final String? initialSessionId;
  http.Client? _streamClient;
  bool _stopRequested = false;
  String _assistantDraft = '';
  int _selectionRevision = 0;

  @override
  AgentViewState build() {
    ref.onDispose(() => _streamClient?.close());
    Future<void>.microtask(bootstrap);
    return const AgentViewState();
  }

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null);
    try {
      await _loadSessions();
      final requestedSession = initialSessionId?.trim();
      if (requestedSession != null && requestedSession.isNotEmpty) {
        await selectSession(requestedSession);
      } else if (state.sessions.isEmpty) {
        await createSession();
      } else {
        await selectSession(state.sessions.first.id);
      }
    } catch (error) {
      state = state.copyWith(error: _formatRequestError(error));
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> _loadSessions() async {
    final response = await ref.read(apiClientProvider).get('/agent/sessions');
    final data = response.data as Map<String, dynamic>? ?? {};
    final sessions = (data['sessions'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AgentSessionSummary.fromJson)
        .toList();
    state = state.copyWith(sessions: sessions);
  }

  Future<void> createSession() async {
    if (state.streaming) return;
    _selectionRevision += 1;
    final response = await ref
        .read(apiClientProvider)
        .post('/agent/sessions', data: {'title': '新会话'});
    final session = AgentSessionSummary.fromJson(
      response.data as Map<String, dynamic>,
    );
    _assistantDraft = '';
    state = state.copyWith(
      sessions: [session, ...state.sessions],
      sessionId: session.id,
      activeRunId: null,
      timeline: const [],
      error: null,
    );
  }

  Future<void> selectSession(String sessionId) async {
    if (state.streaming) return;
    final revision = ++_selectionRevision;
    final dio = ref.read(apiClientProvider);
    final responses = await Future.wait([
      dio.get('/agent/sessions/$sessionId/messages'),
      dio.get(
        '/agent/sessions/$sessionId/confirmations',
        queryParameters: {'status': 'pending', 'limit': 100},
      ),
    ]);
    final data = responses[0].data as Map<String, dynamic>? ?? {};
    final messages = (data['messages'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AgentMessageRecord.fromJson)
        .map(AgentTimelineItem.fromMessage)
        .toList();
    final confirmations = (responses[1].data as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AgentConfirmation.fromJson)
        .where((confirmation) => confirmation.status == 'pending')
        .map(AgentTimelineItem.confirmation);
    if (revision != _selectionRevision) return;
    _assistantDraft = '';
    state = state.copyWith(
      sessionId: sessionId,
      activeRunId: null,
      timeline: [...messages, ...confirmations],
      error: null,
    );
  }

  Future<void> sendPrompt(String rawText) async {
    if (state.streaming) return;
    final text = rawText.trim();
    if (text.isEmpty) return;
    if (state.sessionId == null) await createSession();

    _stopRequested = false;
    _assistantDraft = '';
    state = state.copyWith(
      streaming: true,
      error: null,
      timeline: [
        ...state.timeline,
        AgentTimelineItem.user(text),
        AgentTimelineItem.assistantDraft(),
      ],
    );

    final local = ref.read(localSettingsProvider);
    final base = Uri.parse(local.baseUrl);
    final uri = base.replace(
      path: '${base.path}/agent/sse',
      queryParameters: {'message': text, 'session_id': ?state.sessionId},
    );
    final client = ref.read(agentStreamClientFactoryProvider)();
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
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          applyEvent(AgentStreamEvent.fromJson(decoded));
        }
      }
    } catch (error) {
      if (!_stopRequested) {
        final message = _formatRequestError(error);
        state = state.copyWith(
          timeline: _replaceDraft(AgentTimelineItem.error(message)),
        );
      }
    } finally {
      client.close();
      if (identical(_streamClient, client)) _streamClient = null;
      state = state.copyWith(streaming: false);
      _stopRequested = false;
      unawaited(_loadSessions());
    }
  }

  void applyEvent(AgentStreamEvent event) {
    var timeline = state.timeline;
    var sessionId = state.sessionId;
    var activeRunId = state.activeRunId;
    switch (event.type) {
      case AgentStreamEventType.start:
        sessionId = event.sessionId ?? sessionId;
        activeRunId = event.runId;
      case AgentStreamEventType.assistantDelta:
        _assistantDraft += event.content;
        timeline = _replaceDraft(AgentTimelineItem.assistant(_assistantDraft));
      case AgentStreamEventType.toolCall:
      case AgentStreamEventType.toolResult:
        final callId = event.payload['tool_call_id'];
        final index = callId == null
            ? -1
            : timeline.indexWhere(
                (item) =>
                    (item.kind == AgentTimelineKind.toolCall ||
                        item.kind == AgentTimelineKind.toolResult) &&
                    item.event?['tool_call_id'] == callId,
              );
        final payload = {
          if (index >= 0) ...timeline[index].event!,
          ...event.payload,
        };
        final item = event.type == AgentStreamEventType.toolResult
            ? AgentTimelineItem.toolResult(payload)
            : AgentTimelineItem.toolCall(payload);
        timeline = [...timeline];
        if (index < 0) {
          timeline.add(item);
        } else if (timeline[index].kind != AgentTimelineKind.toolResult ||
            event.type == AgentStreamEventType.toolResult) {
          timeline[index] = item;
        }
      case AgentStreamEventType.confirmationRequired:
        final confirmation = event.confirmation;
        if (confirmation != null &&
            !timeline.any(
              (item) =>
                  item.kind == AgentTimelineKind.confirmation &&
                  item.confirmation?.id == confirmation.id,
            )) {
          timeline = [
            ...timeline,
            AgentTimelineItem.confirmation(confirmation),
          ];
        }
      case AgentStreamEventType.contextSummary:
        timeline = [...timeline, AgentTimelineItem.notice('较早的对话已压缩')];
      case AgentStreamEventType.usage:
        timeline = [
          ...timeline,
          AgentTimelineItem.notice(
            '模型用量',
            details: prettyJson(event.payload['usage']),
          ),
        ];
      case AgentStreamEventType.error:
        timeline = _replaceDraft(
          AgentTimelineItem.error(_formatEventError(event.payload)),
        );
        activeRunId = null;
      case AgentStreamEventType.finalResult:
        final message = event.message;
        if (message != null && message.trim().isNotEmpty) {
          timeline = _replaceDraft(AgentTimelineItem.assistant(message));
        }
        activeRunId = null;
      case AgentStreamEventType.unknown:
        break;
    }
    state = state.copyWith(
      timeline: timeline,
      sessionId: sessionId,
      activeRunId: activeRunId,
    );
  }

  Future<void> decideConfirmation(
    AgentConfirmation confirmation,
    bool approved,
  ) async {
    if (state.decidingConfirmationIds.contains(confirmation.id)) return;
    state = state.copyWith(
      decidingConfirmationIds: {
        ...state.decidingConfirmationIds,
        confirmation.id,
      },
    );
    try {
      final response = await ref
          .read(apiClientProvider)
          .post(
            '/agent/confirmations/${confirmation.id}/decide',
            data: {'approved': approved},
          );
      final result = AgentRunResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      state = state.copyWith(
        timeline: state.timeline
            .where(
              (item) =>
                  item.kind != AgentTimelineKind.confirmation ||
                  item.confirmation?.id != confirmation.id,
            )
            .toList(),
      );
      for (final event in result.events) {
        applyEvent(AgentStreamEvent.fromJson(event));
      }
      await _loadSessions();
    } on DioException catch (error) {
      state = state.copyWith(
        timeline: [
          ...state.timeline,
          AgentTimelineItem.error(_formatAgentErrorMessage(error)),
        ],
      );
    } finally {
      state = state.copyWith(
        decidingConfirmationIds: {...state.decidingConfirmationIds}
          ..remove(confirmation.id),
      );
    }
  }

  Future<void> redo() async {
    if (state.sessionId == null || state.streaming) return;
    try {
      final response = await ref
          .read(apiClientProvider)
          .post('/agent/sessions/${state.sessionId}/redo');
      final result = AgentRunResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      for (final event in result.events) {
        applyEvent(AgentStreamEvent.fromJson(event));
      }
    } on DioException catch (error) {
      state = state.copyWith(
        timeline: [
          ...state.timeline,
          AgentTimelineItem.error(_formatAgentErrorMessage(error)),
        ],
      );
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    _streamClient?.close();
    final runId = state.activeRunId;
    if (runId == null) {
      state = state.copyWith(streaming: false);
      return;
    }
    await ref.read(apiClientProvider).post('/agent/runs/$runId/stop');
    state = state.copyWith(
      streaming: false,
      activeRunId: null,
      timeline: [...state.timeline, AgentTimelineItem.notice('已请求停止')],
    );
  }

  Future<void> clearSession() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    await ref.read(apiClientProvider).post('/agent/sessions/$sessionId/clear');
    _assistantDraft = '';
    state = state.copyWith(timeline: const [], activeRunId: null, error: null);
    await _loadSessions();
  }

  List<AgentTimelineItem> _replaceDraft(AgentTimelineItem item) {
    final timeline = [...state.timeline];
    final index = timeline.lastIndexWhere(
      (candidate) => candidate.kind == AgentTimelineKind.assistantDraft,
    );
    final replaceIndex = index >= 0
        ? index
        : state.streaming &&
              timeline.isNotEmpty &&
              timeline.last.kind == AgentTimelineKind.assistant
        ? timeline.length - 1
        : -1;
    if (replaceIndex >= 0) {
      timeline[replaceIndex] = item;
    } else if (item.kind == AgentTimelineKind.assistant ||
        item.kind == AgentTimelineKind.error) {
      timeline.add(item);
    }
    return timeline;
  }

  String _formatEventError(Map<String, dynamic> event) {
    final message = event['message']?.toString() ?? 'Agent 执行失败';
    final fix = event['suggested_fix']?.toString();
    return fix == null || fix.isEmpty ? message : '$message\n$fix';
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

  String _formatRequestError(Object error) {
    if (error is DioException) return _formatAgentErrorMessage(error);
    return 'Agent 工作台加载失败，请检查连接后重试。';
  }
}
