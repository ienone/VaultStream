import '../models/system_setting.dart';

dynamic getSettingValue(List<SystemSetting> settings, String key, dynamic fallback) {
  try {
    return settings.firstWhere((s) => s.key == key).value;
  } catch (_) {
    return fallback;
  }
}

int parseIntSetting(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

double parseDoubleSetting(dynamic value, double fallback) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

