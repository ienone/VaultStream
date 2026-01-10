// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'system_setting.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SystemSetting _$SystemSettingFromJson(Map<String, dynamic> json) =>
    _SystemSetting(
      key: json['key'] as String,
      value: json['value'],
      category: json['category'] as String?,
      description: json['description'] as String?,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.parse(json['updated_at'] as String),
    );

Map<String, dynamic> _$SystemSettingToJson(_SystemSetting instance) =>
    <String, dynamic>{
      'key': instance.key,
      'value': instance.value,
      'category': instance.category,
      'description': instance.description,
      'updated_at': instance.updatedAt?.toIso8601String(),
    };
