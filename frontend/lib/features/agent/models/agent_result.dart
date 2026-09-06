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
    required this.sessionId,
    required this.runId,
    required this.toolName,
    required this.permissionLevel,
    required this.status,
    required this.summary,
    this.args = const {},
  });

  factory AgentConfirmation.fromJson(Map<String, dynamic> json) {
    final args = json['args'];
    return AgentConfirmation(
      id: json['id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      runId: json['run_id']?.toString() ?? '',
      toolName: json['tool_name']?.toString() ?? '',
      permissionLevel: json['permission_level']?.toString() ?? 'write',
      status: json['status']?.toString() ?? 'pending',
      summary: json['summary']?.toString() ?? '',
      args: args is Map<String, dynamic> ? args : const {},
    );
  }

  final String id;
  final String sessionId;
  final String runId;
  final String toolName;
  final String permissionLevel;
  final String status;
  final String summary;
  final Map<String, dynamic> args;
}

enum AgentCitationKind { content, event, timepoint }

class AgentCitation {
  const AgentCitation({
    required this.kind,
    required this.title,
    required this.matchSource,
    this.contentId = '',
    this.eventId = '',
    this.mediaAssetId = '',
    this.contentTitle,
    this.startSeconds,
    this.endSeconds,
    this.url = '',
    this.chunkTitle,
    this.sourceText,
  });

  factory AgentCitation.fromJson(
    Map<String, dynamic> json, {
    AgentCitationKind fallbackKind = AgentCitationKind.content,
  }) {
    final rawKind = json['kind']?.toString();
    final kind = switch (rawKind) {
      'event' => AgentCitationKind.event,
      'timepoint' => AgentCitationKind.timepoint,
      'content' => AgentCitationKind.content,
      _ => fallbackKind,
    };
    return AgentCitation(
      kind: kind,
      contentId: json['content_id']?.toString() ?? '',
      eventId: json['event_id']?.toString() ?? '',
      mediaAssetId: json['media_asset_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '无标题',
      contentTitle: json['content_title']?.toString(),
      startSeconds: (json['start_seconds'] as num?)?.toDouble(),
      endSeconds: (json['end_seconds'] as num?)?.toDouble(),
      url: json['url']?.toString() ?? '',
      matchSource: json['match_source']?.toString() ?? '',
      chunkTitle: json['chunk_title']?.toString(),
      sourceText: json['source_text']?.toString(),
    );
  }

  final AgentCitationKind kind;
  final String contentId;
  final String eventId;
  final String mediaAssetId;
  final String title;
  final String? contentTitle;
  final double? startSeconds;
  final double? endSeconds;
  final String url;
  final String matchSource;
  final String? chunkTitle;
  final String? sourceText;

  String? get appRoute {
    switch (kind) {
      case AgentCitationKind.content:
        return contentId.isEmpty ? null : '/collection/$contentId';
      case AgentCitationKind.event:
        return eventId.isEmpty ? null : '/events/$eventId';
      case AgentCitationKind.timepoint:
        if (contentId.isEmpty || mediaAssetId.isEmpty || startSeconds == null) {
          return null;
        }
        final start = startSeconds!;
        final startValue = start == start.truncateToDouble()
            ? start.toInt().toString()
            : start.toString();
        return Uri(
          path: '/collection/$contentId',
          queryParameters: {'t': startValue, 'media_asset': mediaAssetId},
        ).toString();
    }
  }

  String get displayLabel {
    switch (kind) {
      case AgentCitationKind.content:
        return contentId.isEmpty ? title : '#$contentId $title';
      case AgentCitationKind.event:
        return eventId.isEmpty ? title : '事件 #$eventId $title';
      case AgentCitationKind.timepoint:
        final seconds = startSeconds;
        if (seconds == null) return title;
        final totalSeconds = seconds.floor();
        final minutes = totalSeconds ~/ 60;
        final remainder = (totalSeconds % 60).toString().padLeft(2, '0');
        return '$minutes:$remainder $title';
    }
  }
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
  final groups = <List<AgentCitation>>[];
  for (final group in const [
    ('items', AgentCitationKind.content),
    ('events', AgentCitationKind.event),
    ('timepoints', AgentCitationKind.timepoint),
  ]) {
    final items = result[group.$1];
    if (items is! List) continue;
    groups.add(
      items
          .whereType<Map<String, dynamic>>()
          .map((item) => AgentCitation.fromJson(item, fallbackKind: group.$2))
          .toList(growable: false),
    );
  }
  final citations = <AgentCitation>[];
  final longest = groups.fold<int>(
    0,
    (length, group) => group.length > length ? group.length : length,
  );
  for (var index = 0; index < longest; index += 1) {
    for (final group in groups) {
      if (index < group.length) citations.add(group[index]);
    }
  }
  return List.unmodifiable(citations);
}

String? actionSummaryFromToolResult(Map<String, dynamic> event) {
  if (event['tool'] != 'organize_knowledge_event') return null;
  final result = event['result'];
  if (result is! Map<String, dynamic>) return null;
  final eventId = result['event_id']?.toString() ?? '';
  final title = result['title']?.toString() ?? '知识事件';
  final contentId = result['content_id']?.toString() ?? '';
  final role = _eventRoleLabel(result['role']?.toString());
  final evidence = _evidenceStateLabel(result['evidence_state']?.toString());
  final action = result['action']?.toString();
  if (eventId.isEmpty || contentId.isEmpty) return null;
  return action == 'create'
      ? '已创建事件 #$eventId“$title”，内容 #$contentId 作为$role加入，证据状态为$evidence。'
      : '已将内容 #$contentId 作为$role加入事件 #$eventId“$title”，证据状态为$evidence。';
}

String _eventRoleLabel(String? value) =>
    const {
      'source': '原始来源',
      'report': '独立报道',
      'commentary': '评论观点',
      'background': '背景资料',
      'correction': '更正信息',
      'evidence': '现场证据',
    }[value] ??
    '事件成员';

String _evidenceStateLabel(String? value) =>
    const {
      'unverified': '尚未确认',
      'confirmed': '已确认',
      'disputed': '存在争议',
      'viewpoint': '观点',
    }[value] ??
    '未分类';
