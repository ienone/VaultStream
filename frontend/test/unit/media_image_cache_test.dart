import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/media/asset_image_provider.dart';
import 'package:frontend/core/providers/local_settings_provider.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _Settings extends LocalSettings {
  @override
  LocalSettingsState build() =>
      LocalSettingsState(baseUrl: 'https://server.test', apiToken: 'account-a');
  @override
  Future<void> setApiToken(String token) async =>
      state = state.copyWith(apiToken: token);
  @override
  Future<void> setBaseUrl(String url) async =>
      state = state.copyWith(baseUrl: url);
}

Future<void> _load(AssetImageProvider provider) async {
  final done = Completer<void>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, synchronous) {
      image.dispose();
      if (!done.isCompleted) done.complete();
    },
    onError: (Object error, StackTrace? stack) {
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  try {
    await done.future;
  } finally {
    stream.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'signature refresh reuses decoded bytes; file and account changes do not',
    () async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGNkYPjPwMDAxAAGAAsfAQMU4wsAAAAAAElFTkSuQmCC',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttpOverrides(),
      );
      debugNetworkImageHttpClientProvider = () => client;
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.headers.value('X-API-Token'), isNull);
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(bytes);
        await request.response.close();
      });
      final settings = _Settings();
      final container = ProviderContainer(
        overrides: [localSettingsProvider.overrideWith(() => settings)],
      );
      final subscription = container.listen(
        mediaImageCacheScopeProvider,
        (_, _) {},
      );
      addTearDown(() async {
        subscription.close();
        container.dispose();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        debugNetworkImageHttpClientProvider = null;
        client.close(force: true);
        await server.close(force: true);
      });
      var signature = 0;
      Future<void> load([String key = 'asset:1:version-a']) => _load(
        AssetImageProvider(
          'http://127.0.0.1:${server.port}/image?signature=${signature++}',
          cacheKey: key,
          scope: container.read(mediaImageCacheScopeProvider),
        ),
      );
      await load();
      await load();
      expect(requests, 1);
      await load('asset:1:version-b');
      expect(requests, 2);
      await settings.setApiToken('account-b');
      await load();
      expect(requests, 3);
      await settings.setBaseUrl('https://other-server.test');
      await load();
      expect(requests, 4);
    },
  );
}
