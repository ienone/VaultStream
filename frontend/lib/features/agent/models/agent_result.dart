import 'dart:convert';

class AgentSessionSummary {
  const AgentSessionSummary({
    required this.id,
    required this.title,
    required this.status,
    this.lastMessageAt,
    this.pendingConfirmations = 0,
  });

  factory AgentSessionSummary.fromJson(Map<String, dynamic> json) {
    return AgentSessionSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '新会话',
      status: json['status']?.toString() ?? 'active',
      lastMessageAt: DateTime.tryParse(
        json['last_message_at']?.toString() ?? '',
      ),
      pendingConfirmations:
          (json['pending_confirmations'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final String status;
  final DateTime? lastMessageAt;
  final int pendingConfirmations;
}

class AgentMessageRecord {
  const AgentMessageRecord({
    required this.id,
    required this.role,
    required this.content,
    this.runId,
    this.payload = const {},
  });

  factory AgentMessageRecord.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return AgentMessageRecord(
      id: (json['id'] as num?)?.toInt() ?? 0,
      runId: json['run_id']?.toString(),
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      payload: payload is Map<String, dynamic> ? payload : const {},
    );
  }

  final int id;
  final String? runId;
  final String role;
  final String content;
  final Map<String, dynamic> payload;
}

class AgentConfirmation {
  const AgentConfirmation({
    required this.id,
    required this.toolName,
    required this.permissionLevel,
    required this.summary,
    this.args = const {},
  });

  factory AgentConfirmation.fromJson(Map<String, dynamic> json) {
    final args = json['args'];
    return AgentConfirmation(
      id: json['id']?.toString() ?? '',
      toolName: json['tool_name']?.toString() ?? '',
      permissionLevel: json['permission_level']?.toString() ?? 'write',
      summary: json['summary']?.toString() ?? '',
      args: args is Map<String, dynamic> ? args : const {},
    );
  }

  final String id;
  final String toolName;
  final String permissionLevel;
  final String summary;
  final Map<String, dynamic> args;
}

class AgentCitation {
  const AgentCitation({
    required this.contentId,
    required this.title,
    required this.url,
    required this.matchSource,
    this.chunkTitle,
    this.sourceText,
  });

  factory AgentCitation.fromJson(Map<String, dynamic> json) {
    return AgentCitation(
      contentId: json['content_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '无标题',
      url: json['url']?.toString() ?? '',
      matchSource: json['match_source']?.toString() ?? '',
      chunkTitle: json['chunk_title']?.toString(),
      sourceText: json['source_text']?.toString(),
    );
  }

  final String contentId;
  final String title;
  final String url;
  final String matchSource;
  final String? chunkTitle;
  final String? sourceText;
}

class AgentRunResponse {
  const AgentRunResponse({
    required this.sessionId,
    required this.runId,
    required this.status,
    required this.message,
    this.tool,
    this.events = const [],
    this.confirmation,
  });

  factory AgentRunResponse.fromJson(Map<String, dynamic> json) {
    final events = (json['events'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final confirmation = json['confirmation'];
    return AgentRunResponse(
      sessionId: json['session_id']?.toString() ?? '',
      runId: json['run_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      tool: json['tool']?.toString(),
      message: json['message']?.toString() ?? '',
      events: events,
      confirmation: confirmation is Map<String, dynamic>
          ? AgentConfirmation.fromJson(confirmation)
          : null,
    );
  }

  final String sessionId;
  final String runId;
  final String status;
  final String? tool;
  final String message;
  final List<Map<String, dynamic>> events;
  final AgentConfirmation? confirmation;
}

String prettyJson(Object? value) {
  if (value == null) return '';
  return const JsonEncoder.withIndent('  ').convert(value);
}

List<AgentCitation> citationsFromToolResult(Map<String, dynamic> event) {
  final result = event['result'];
  if (result is! Map<String, dynamic>) return const [];
  final items = result['items'];
  if (items is! List) return const [];
  return items
      .whereType<Map<String, dynamic>>()
      .map(AgentCitation.fromJson)
      .toList(growable: false);
}
