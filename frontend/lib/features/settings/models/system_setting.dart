import 'package:freezed_annotation/freezed_annotation.dart';

part 'system_setting.freezed.dart';
part 'system_setting.g.dart';

@freezed
abstract class SystemSetting with _$SystemSetting {
  const SystemSetting._();

  const factory SystemSetting({
    required String key,
    required dynamic value,
    String? category,
    String? description,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _SystemSetting;

  factory SystemSetting.fromJson(Map<String, dynamic> json) =>
      _$SystemSettingFromJson(json);
}
