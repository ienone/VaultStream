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

  test('recognizes audio independently from video', () {
    expect(isAudio('local://vaultstream/audio/episode.MP3?download=1'), isTrue);
    expect(isAudio('https://example.test/episode.opus'), isTrue);
    expect(isAudio('https://example.test/video.mp4'), isFalse);
    expect(isVideo('https://example.test/video.mp4'), isTrue);
  });

  test('playable remote media bypasses the image proxy', () {
    expect(
      mapPlayableUrl('https://cdn.example.test/episode.mp3', apiBaseUrl),
      'https://cdn.example.test/episode.mp3',
    );
    expect(
      mapPlayableUrl('local://vaultstream/audio/episode.mp3', apiBaseUrl),
      'http://localhost:8000/api/v1/media/vaultstream/audio/episode.mp3',
    );
  });
}
