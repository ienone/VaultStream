import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/api_client.dart';

void main() {
  group('API client debug log redaction', () {
    test('redacts sensitive request headers', () {
      expect(
        redactDebugLogLine(' X-API-Token: secret-token'),
        ' X-API-Token: <redacted>',
      );
      expect(
        redactDebugLogLine('Authorization: Bearer secret'),
        'Authorization: <redacted>',
      );
      expect(redactDebugLogLine('cookie: sid=secret'), 'cookie: <redacted>');
    });

    test('redacts common token fields in inline logs', () {
      expect(
        redactDebugLogLine('data: {api_token: secret, name: demo}'),
        'data: {api_token: <redacted>, name: demo}',
      );
      expect(
        redactDebugLogLine('bot-token=secret-value'),
        'bot-token=<redacted>',
      );
    });
  });
}
