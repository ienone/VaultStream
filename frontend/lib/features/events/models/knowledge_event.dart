class KnowledgeEventSummary {
  const KnowledgeEventSummary({
    required this.id,
    required this.title,
    required this.status,
    required this.memberCount,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.firstOccurredAt,
    this.lastOccurredAt,
    this.latestMemberTitle,
  });

  factory KnowledgeEventSummary.fromJson(Map<String, dynamic> json) =>
      KnowledgeEventSummary(
        id: json['id'] as int,
        title: json['title'] as String,
        description: json['description'] as String?,
        status: json['status'] as String,
        memberCount: json['member_count'] as int,
        firstOccurredAt: _date(json['first_occurred_at']),
        lastOccurredAt: _date(json['last_occurred_at']),
        latestMemberTitle: json['latest_member_title'] as String?,
        createdAt: _requiredDate(json['created_at']),
        updatedAt: _requiredDate(json['updated_at']),
      );

  final int id;
  final String title;
  final String? description;
  final String status;
  final int memberCount;
  final DateTime? firstOccurredAt;
  final DateTime? lastOccurredAt;
  final String? latestMemberTitle;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class KnowledgeEventMember {
  const KnowledgeEventMember({
    required this.id,
    required this.contentId,
    required this.role,
    required this.evidenceState,
    required this.addedBy,
    required this.addedAt,
    required this.updatedAt,
    required this.platform,
    required this.url,
    required this.contentCreatedAt,
    this.note,
    this.title,
    this.summary,
    this.publishedAt,
  });

  factory KnowledgeEventMember.fromJson(Map<String, dynamic> json) =>
      KnowledgeEventMember(
        id: json['id'] as int,
        contentId: json['content_id'] as int,
        role: json['role'] as String,
        evidenceState: json['evidence_state'] as String,
        note: json['note'] as String?,
        addedBy: json['added_by'] as String,
        addedAt: _requiredDate(json['added_at']),
        updatedAt: _requiredDate(json['updated_at']),
        title: json['title'] as String?,
        summary: json['summary'] as String?,
        platform: json['platform'] as String,
        url: json['url'] as String,
        publishedAt: _date(json['published_at']),
        contentCreatedAt: _requiredDate(json['content_created_at']),
      );

  final int id;
  final int contentId;
  final String role;
  final String evidenceState;
  final String? note;
  final String addedBy;
  final DateTime addedAt;
  final DateTime updatedAt;
  final String? title;
  final String? summary;
  final String platform;
  final String url;
  final DateTime? publishedAt;
  final DateTime contentCreatedAt;

  DateTime get occurredAt => publishedAt ?? contentCreatedAt;
}

class KnowledgeEventDetail extends KnowledgeEventSummary {
  const KnowledgeEventDetail({
    required super.id,
    required super.title,
    required super.status,
    required super.memberCount,
    required super.createdAt,
    required super.updatedAt,
    required this.members,
    super.description,
    super.firstOccurredAt,
    super.lastOccurredAt,
    super.latestMemberTitle,
  });

  factory KnowledgeEventDetail.fromJson(Map<String, dynamic> json) {
    final summary = KnowledgeEventSummary.fromJson(json);
    return KnowledgeEventDetail(
      id: summary.id,
      title: summary.title,
      description: summary.description,
      status: summary.status,
      memberCount: summary.memberCount,
      firstOccurredAt: summary.firstOccurredAt,
      lastOccurredAt: summary.lastOccurredAt,
      latestMemberTitle: summary.latestMemberTitle,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      members: (json['members'] as List<dynamic>? ?? const [])
          .map(
            (item) => KnowledgeEventMember.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  final List<KnowledgeEventMember> members;
}

class KnowledgeEventListResponse {
  const KnowledgeEventListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.size,
    required this.hasMore,
  });

  factory KnowledgeEventListResponse.fromJson(Map<String, dynamic> json) =>
      KnowledgeEventListResponse(
        items: (json['items'] as List<dynamic>? ?? const [])
            .map(
              (item) => KnowledgeEventSummary.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        total: json['total'] as int,
        page: json['page'] as int,
        size: json['size'] as int,
        hasMore: json['has_more'] as bool,
      );

  final List<KnowledgeEventSummary> items;
  final int total;
  final int page;
  final int size;
  final bool hasMore;
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

DateTime _requiredDate(Object? value) =>
    _date(value) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
