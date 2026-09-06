import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/media/media_asset.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/features/player/global_playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

// Replace only the OS decoder. The provider, persistence, Dio and manifest
// parsing remain real; this does not establish actual media decoding quality.
class _Decoder extends VideoPlayerPlatform {
  String? url;
  Duration position = Duration.zero;
  bool playing = false;
  double speed = 1;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<int> createWithOptions(VideoCreationOptions options) async {
    url = options.dataSource.uri;
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 3),
      size: const Size(640, 360),
    ),
  );
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> play(int playerId) async {
    playing = true;
  }

  @override
  Future<void> pause(int playerId) async {
    playing = false;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    this.position = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    this.speed = speed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'restart reloads asset manifest and resumes from paused position',
    () async {
      const asset = MediaAsset(
        id: 7,
        contentId: 42,
        mediaType: MediaType.video,
        role: MediaRole.attachment,
        purpose: MediaPurpose.playback,
        sources: [
          MediaSource(
            url: 'https://media.test/expired',
            sourceKind: MediaSourceKind.localSigned,
          ),
        ],
      );
      const request = PlaybackRequest(
        contentId: 42,
        title: '恢复视频',
        urls: [],
        audioOnly: false,
        mediaAsset: asset,
      );
      final snapshot = PlaybackSessionSnapshot(
        request: request,
        queue: const [],
        position: const Duration(seconds: 42),
        playbackSpeed: 1.5,
        videoAudioOnly: true,
      );
      final serialized = jsonEncode(snapshot.toJson());
      expect(serialized, isNot(contains('https://media.test/expired')));
      SharedPreferences.setMockInitialValues({
        GlobalPlaybackController.playbackSessionStorageKey: serialized,
      });
      final previous = VideoPlayerPlatform.instance;
      final decoder = _Decoder();
      VideoPlayerPlatform.instance = decoder;
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost/api/v1'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  ...asset.toJson(),
                  'sources': [
                    {
                      'url': 'https://media.test/fresh',
                      'source_kind': 'local_signed',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(dio)],
      );
      final ready = Completer<void>();
      container.listen(globalPlaybackProvider, (_, next) {
        if (next.initialized && !ready.isCompleted) ready.complete();
      });
      await ready.future.timeout(const Duration(seconds: 3));
      final controller = container.read(globalPlaybackProvider.notifier);
      try {
        expect(requests.single.path, '/media/assets/7/manifest');
        expect(requests.single.queryParameters, {'purpose': 'playback'});
        expect(container.read(globalPlaybackProvider).initialized, isTrue);
        expect(decoder.url, 'https://media.test/fresh');
        expect(decoder.position, const Duration(seconds: 42));
        expect(controller.videoController!.value.playbackSpeed, 1.5);
        expect(decoder.playing, isFalse);
        await controller.togglePlayback();
        expect(decoder.playing, isTrue);
        expect(decoder.speed, 1.5);
        await controller.close();
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.containsKey(GlobalPlaybackController.playbackSessionStorageKey),
          isFalse,
        );
      } finally {
        await controller.close();
        container.dispose();
        dio.close();
        VideoPlayerPlatform.instance = previous;
      }
    },
  );
}
