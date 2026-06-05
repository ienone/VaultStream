import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/utils/media_utils.dart';

void main() {
  const apiBaseUrl = 'http://localhost:8000/api/v1';

  test('maps local protocol to protected media API', () {
    expect(
      mapUrl('local://vaultstream/blobs/sha256/aa/bb/file.webp', apiBaseUrl),
      'http://localhost:8000/api/v1/media/vaultstream/blobs/sha256/aa/bb/file.webp',
    );
  });

  test('maps legacy static media URL to protected media API', () {
    expect(
      mapUrl('/media/vaultstream/blobs/sha256/aa/bb/file.webp', apiBaseUrl),
      'http://localhost:8000/api/v1/media/vaultstream/blobs/sha256/aa/bb/file.webp',
    );
  });

  test('maps bare blob key to protected media API', () {
    expect(
      mapUrl('vaultstream/blobs/sha256/aa/bb/file.webp', apiBaseUrl),
      'http://localhost:8000/api/v1/media/vaultstream/blobs/sha256/aa/bb/file.webp',
    );
  });
}
