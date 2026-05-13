import 'dart:convert';

class AgentRunResponse {
  const AgentRunResponse({required this.tool, required this.result});

  factory AgentRunResponse.fromJson(Map<String, dynamic> json) {
    final tool = (json['tool'] as String?) ?? 'unknown';
    final result = json['result'] is Map<String, dynamic>
        ? json['result'] as Map<String, dynamic>
        : <String, dynamic>{};
    return AgentRunResponse(
      tool: tool,
      result: AgentResult.fromToolResult(tool, result),
    );
  }

  final String tool;
  final AgentResult result;
}

sealed class AgentResult {
  const AgentResult();

  factory AgentResult.fromToolResult(String tool, Map<String, dynamic> result) {
    return switch (tool) {
      'search_content' => SearchContentResult.fromJson(result),
      'list_groups' => ListGroupsResult.fromJson(result),
      _ => RawAgentResult(result),
    };
  }

  String toDisplayText();
}

class SearchContentResult extends AgentResult {
  const SearchContentResult(this.items);

  factory SearchContentResult.fromJson(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AgentSearchItem.fromJson)
        .toList();
    return SearchContentResult(items);
  }

  final List<AgentSearchItem> items;

  @override
  String toDisplayText() {
    if (items.isEmpty) return '未找到相关内容。';
    final lines = <String>['共 ${items.length} 条结果:'];
    for (final item in items.take(6)) {
      final title = item.title?.trim();
      lines.add(
        '- [${item.contentId ?? "-"}] ${title?.isNotEmpty == true ? title : item.url ?? "无标题"}',
      );
    }
    return lines.join('\n');
  }
}

class AgentSearchItem {
  const AgentSearchItem({this.contentId, this.title, this.url});

  factory AgentSearchItem.fromJson(Map<String, dynamic> json) {
    return AgentSearchItem(
      contentId: json['content_id'],
      title: json['title'] as String?,
      url: json['url'] as String?,
    );
  }

  final Object? contentId;
  final String? title;
  final String? url;
}

class ListGroupsResult extends AgentResult {
  const ListGroupsResult(this.groups);

  factory ListGroupsResult.fromJson(Map<String, dynamic> json) {
    final groups = (json['groups'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AgentGroup.fromJson)
        .toList();
    return ListGroupsResult(groups);
  }

  final List<AgentGroup> groups;

  @override
  String toDisplayText() {
    if (groups.isEmpty) return '当前没有可用群组。';
    final lines = <String>['可用群组 ${groups.length} 个:'];
    for (final group in groups.take(8)) {
      lines.add('- ${group.title ?? group.chatId} (${group.chatId})');
    }
    return lines.join('\n');
  }
}

class AgentGroup {
  const AgentGroup({required this.chatId, this.title});

  factory AgentGroup.fromJson(Map<String, dynamic> json) {
    return AgentGroup(
      chatId: json['chat_id']?.toString() ?? '',
      title: json['title'] as String?,
    );
  }

  final String chatId;
  final String? title;
}

class RawAgentResult extends AgentResult {
  const RawAgentResult(this.value);

  final Map<String, dynamic> value;

  @override
  String toDisplayText() => const JsonEncoder.withIndent('  ').convert(value);
}
