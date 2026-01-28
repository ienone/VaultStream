import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/review/models/distribution_rule.dart';

void main() {
  group('DistributionRule Model', () {
    test('fromJson should parse valid JSON correctly', () {
      final Map<String, dynamic> json = {
        'id': 1,
        'name': 'Test Rule',
        'match_conditions': {
          'tags': ['tag1'],
          'is_nsfw': false,
        },
        'enabled': true,
        'priority': 10,
        'nsfw_policy': 'block',
        'approval_required': false,
        'created_at': '2024-01-01T10:00:00Z',
        'updated_at': '2024-01-01T10:00:00Z',
      };

      final rule = DistributionRule.fromJson(json);

      expect(rule.id, 1);
      expect(rule.name, 'Test Rule');
      expect(rule.matchConditions['tags'], ['tag1']);
      expect(rule.matchConditions['is_nsfw'], false);
      expect(rule.enabled, true);
    });

    test('fromJson should handle optional fields', () {
      final Map<String, dynamic> json = {
        'id': 2,
        'name': 'Minimal Rule',
        'match_conditions': <String, dynamic>{}, // Fix: Ensure inner map is typed
        'created_at': '2024-01-01T10:00:00Z',
        'updated_at': '2024-01-01T10:00:00Z',
      };

      final rule = DistributionRule.fromJson(json);

      expect(rule.id, 2);
      expect(rule.description, null);
      expect(rule.rateLimit, null);
    });
  });
}
