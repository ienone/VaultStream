import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/media/media_candidate_resolver.dart';

void main() {
  test('按后端顺序执行候选并去除空值和重复 URL', () {
    final resolver = MediaCandidateResolver([
      'https://server.test/a.webp',
      ' ',
      'https://server.test/a.webp',
      'https://proxy.test/a',
      'https://origin.test/a.jpg',
    ]);

    expect(resolver.current, 'https://server.test/a.webp');
    expect(resolver.moveNext(), isTrue);
    expect(resolver.current, 'https://proxy.test/a');
    expect(resolver.moveNext(), isTrue);
    expect(resolver.current, 'https://origin.test/a.jpg');
    expect(resolver.moveNext(), isFalse);
  });

  test('无候选时保持稳定空状态', () {
    final resolver = MediaCandidateResolver(const []);

    expect(resolver.current, isNull);
    expect(resolver.hasNext, isFalse);
    expect(resolver.moveNext(), isFalse);
  });
}
