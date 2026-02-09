import 'package:freezed_annotation/freezed_annotation.dart';
import 'target_usage_info.dart';

part 'target_list_response.freezed.dart';
part 'target_list_response.g.dart';

@freezed
abstract class TargetListResponse with _$TargetListResponse {
  const factory TargetListResponse({
    required int total,
    required List<TargetUsageInfo> targets,
  }) = _TargetListResponse;

  factory TargetListResponse.fromJson(Map<String, dynamic> json) =>
      _$TargetListResponseFromJson(json);
}
