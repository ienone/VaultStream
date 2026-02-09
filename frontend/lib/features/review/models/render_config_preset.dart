import 'package:freezed_annotation/freezed_annotation.dart';

part 'render_config_preset.freezed.dart';
part 'render_config_preset.g.dart';

@freezed
abstract class RenderConfigPreset with _$RenderConfigPreset {
  const factory RenderConfigPreset({
    required String id,
    required String name,
    String? description,
    required Map<String,dynamic> config,
    @JsonKey(name: 'is_builtin') @Default(false) bool isBuiltin,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _RenderConfigPreset;

  factory RenderConfigPreset.fromJson(Map<String, dynamic> json) =>
      _$RenderConfigPresetFromJson(json);
}
