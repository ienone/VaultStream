import 'package:freezed_annotation/freezed_annotation.dart';

part 'pushed_record.freezed.dart';
part 'pushed_record.g.dart';

@freezed
abstract class PushedRecord with _$PushedRecord {
  const PushedRecord._();

  const factory PushedRecord({
    required int id,
    @JsonKey(name: 'content_id') required int contentId,
    @JsonKey(name: 'target_platform') required String targetPlatform,
    @JsonKey(name: 'target_id') required String targetId,
    @JsonKey(name: 'message_id') String? messageId,
    @JsonKey(name: 'push_status') required String pushStatus,
    @JsonKey(name: 'error_message') String? errorMessage,
    @JsonKey(name: 'pushed_at') required DateTime pushedAt,
  }) = _PushedRecord;

  bool get isSuccess => pushStatus == 'success';
  bool get isFailed => pushStatus == 'failed';
  bool get isPending => pushStatus == 'pending';

  factory PushedRecord.fromJson(Map<String, dynamic> json) =>
      _$PushedRecordFromJson(json);
}

@freezed
abstract class PushedRecordListResponse with _$PushedRecordListResponse {
  const factory PushedRecordListResponse({
    required List<PushedRecord> items,
    required int total,
    required int page,
    required int size,
    @JsonKey(name: 'has_more') required bool hasMore,
  }) = _PushedRecordListResponse;

  factory PushedRecordListResponse.fromJson(Map<String, dynamic> json) =>
      _$PushedRecordListResponseFromJson(json);
}
