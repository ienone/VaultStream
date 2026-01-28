import 'package:freezed_annotation/freezed_annotation.dart';

part 'approval_item.freezed.dart';
part 'approval_item.g.dart';

@freezed
abstract class ApprovalItem with _$ApprovalItem {
  const ApprovalItem._();

  const factory ApprovalItem({
    required int id,
    required String platform,
    required String url,
    required String status,
    @JsonKey(name: 'review_status') required String reviewStatus,
    required List<String> tags,
    @JsonKey(name: 'is_nsfw') required bool isNsfw,
    String? title,
    String? description,
    @JsonKey(name: 'author_name') String? authorName,
    @JsonKey(name: 'cover_url') String? coverUrl,
    @JsonKey(name: 'media_urls') @Default([]) List<String> mediaUrls,
    @JsonKey(name: 'reviewed_at') DateTime? reviewedAt,
    @JsonKey(name: 'reviewed_by') String? reviewedBy,
    @JsonKey(name: 'review_note') String? reviewNote,
    @JsonKey(name: 'created_at') required DateTime createdAt,
  }) = _ApprovalItem;

  bool get isPending => reviewStatus == 'pending';
  bool get isApproved => reviewStatus == 'approved';
  bool get isRejected => reviewStatus == 'rejected';

  factory ApprovalItem.fromJson(Map<String, dynamic> json) =>
      _$ApprovalItemFromJson(json);
}

@freezed
abstract class ReviewAction with _$ReviewAction {
  const factory ReviewAction({
    required String action,
    String? note,
    @JsonKey(name: 'reviewed_by') String? reviewedBy,
  }) = _ReviewAction;

  factory ReviewAction.fromJson(Map<String, dynamic> json) =>
      _$ReviewActionFromJson(json);
}

@freezed
abstract class BatchReviewRequest with _$BatchReviewRequest {
  const factory BatchReviewRequest({
    @JsonKey(name: 'content_ids') required List<int> contentIds,
    required String action,
    String? note,
    @JsonKey(name: 'reviewed_by') String? reviewedBy,
  }) = _BatchReviewRequest;

  factory BatchReviewRequest.fromJson(Map<String, dynamic> json) =>
      _$BatchReviewRequestFromJson(json);
}
