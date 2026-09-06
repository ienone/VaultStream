import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../core/media/media_asset.dart';
import '../../core/media/media_manifest_client.dart';
import '../../core/media/media_segment.dart';
import '../../core/media/media_source_session.dart';
import '../../core/network/api_client.dart';

part 'global_playback_controller.freezed.dart';

const supportedPlaybackSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0];

class PlaybackRequest {
  const PlaybackRequest({
    required this.contentId,
    required this.title,
    required this.urls,
    required this.audioOnly,
    this.mediaAsset,
    this.segments = const [],
  });

  final int contentId;
  final String title;
  final List<String> urls;
  final bool audioOnly;
  final MediaAsset? mediaAsset;
  final List<MediaSegment> segments;

  factory PlaybackRequest.fromJson(Map<String, dynamic> json) =>
      PlaybackRequest(
        contentId: json['content_id'] as int,
        title: json['title'] as String,
        urls: (json['urls'] as List<dynamic>)
            .map((item) => item as String)
            .toList(growable: false),
        audioOnly: json['audio_only'] as bool,
        mediaAsset: json['media_asset'] == null
            ? null
            : MediaAsset.fromJson(
                Map<String, dynamic>.from(json['media_asset'] as Map),
              ),
        segments: (json['segments'] as List<dynamic>? ?? const [])
            .map(
              (item) =>
                  MediaSegment.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'content_id': contentId,
    'title': title,
    'urls': mediaAsset == null ? urls : const <String>[],
    'audio_only': audioOnly,
    'media_asset': mediaAsset == null
        ? null
        : {
            ...mediaAsset!.toJson(),
            'purpose': MediaPurpose.detail.name,
            'sources': const <Object>[],
          },
    'segments': segments.map((item) => item.toJson()).toList(growable: false),
  };

  String get identity => mediaAsset == null
      ? '${audioOnly ? 'audio' : 'video'}:${urls.join('|')}'
      : '${audioOnly ? 'audio' : 'video'}:asset:${mediaAsset!.id}';
}

class PlaybackSessionSnapshot {
  const PlaybackSessionSnapshot({
    required this.request,
    required this.queue,
    required this.position,
    required this.playbackSpeed,
    required this.videoAudioOnly,
  });

  factory PlaybackSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final positionMs = json['position_ms'];
    final speed = json['playback_speed'];
    if (positionMs is! int || positionMs < 0 || speed is! num) {
      throw const FormatException('Invalid playback session snapshot');
    }
    final parsedSpeed = speed.toDouble();
    if (!supportedPlaybackSpeeds.contains(parsedSpeed)) {
      throw const FormatException('Unsupported persisted playback speed');
    }
    return PlaybackSessionSnapshot(
      request: PlaybackRequest.fromJson(
        Map<String, dynamic>.from(json['request'] as Map),
      ),
      queue: (json['queue'] as List<dynamic>? ?? const [])
          .map(
            (item) => PlaybackRequest.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      position: Duration(milliseconds: positionMs),
      playbackSpeed: parsedSpeed,
      videoAudioOnly: json['video_audio_only'] as bool? ?? false,
    );
  }

  final PlaybackRequest request;
  final List<PlaybackRequest> queue;
  final Duration position;
  final double playbackSpeed;
  final bool videoAudioOnly;

  Map<String, dynamic> toJson() => {
    'request': request.toJson(),
    'queue': queue.map((item) => item.toJson()).toList(growable: false),
    'position_ms': position.inMilliseconds,
    'playback_speed': playbackSpeed,
    'video_audio_only': videoAudioOnly,
  };
}

@freezed
abstract class GlobalPlaybackState with _$GlobalPlaybackState {
  const factory GlobalPlaybackState({
    PlaybackRequest? request,
    @Default([]) List<PlaybackRequest> queue,
    @Default(1.0) double playbackSpeed,
    @Default(false) bool videoAudioOnly,
    DateTime? sleepTimerEndsAt,
    @Default(false) bool loading,
    @Default(false) bool initialized,
    MediaFailureKind? failure,
  }) = _GlobalPlaybackState;
}

final globalPlaybackProvider =
    NotifierProvider<GlobalPlaybackController, GlobalPlaybackState>(
      GlobalPlaybackController.new,
    );

class GlobalPlaybackController extends Notifier<GlobalPlaybackState> {
  static const playbackSessionStorageKey = 'global_playback_session_v1';

  VideoPlayerController? _videoController;
  MediaSourceSession? _sourceSession;
  Duration? _pendingSeekPosition;
  int _generation = 0;
  bool _handlingRuntimeFailure = false;
  bool _advancingQueue = false;
  bool _sleepTimerElapsedDuringLoad = false;
  Timer? _sleepTimer;
  DateTime? _lastProgressPersistedAt;
  int _persistRevision = 0;
  bool _restoringSnapshot = false;
  int _playbackIntentVersion = 0;

  VideoPlayerController? get videoController => _videoController;
  Duration get currentPosition =>
      _videoController?.value.position ?? Duration.zero;

  @override
  GlobalPlaybackState build() {
    unawaited(_restorePersistedSession());
    ref.onDispose(() {
      _sleepTimer?.cancel();
      final player = _videoController;
      if (player != null) unawaited(player.dispose());
    });
    return const GlobalPlaybackState();
  }

  Future<void> activate(
    PlaybackRequest request, {
    Duration? initialPosition,
    bool startPlaying = false,
  }) async {
    if (state.request?.identity == request.identity) {
      state = state.copyWith(request: request);
      if (initialPosition != null) {
        _pendingSeekPosition = initialPosition;
        if (state.initialized && _videoController != null) {
          await seekTo(initialPosition);
          if (_pendingSeekPosition == initialPosition) {
            _pendingSeekPosition = null;
          }
        }
      }
      if (startPlaying && state.initialized && _videoController != null) {
        await _videoController!.play();
      }
      await _persistSession();
      return;
    }

    final remainingQueue = state.queue
        .where((queued) => queued.identity != request.identity)
        .toList(growable: false);

    final previous = _videoController;
    final resumeAt = initialPosition ?? Duration.zero;
    _pendingSeekPosition = initialPosition;
    _generation += 1;
    final generation = _generation;
    _handlingRuntimeFailure = false;
    _videoController = null;
    state = state.copyWith(
      request: request,
      queue: remainingQueue,
      loading: true,
      initialized: false,
      failure: null,
    );
    unawaited(_persistSession());
    if (previous != null) {
      previous.removeListener(_onPlaybackValueChanged);
      await previous.dispose();
    }
    if (generation != _generation) return;

    _sourceSession = request.mediaAsset == null
        ? MediaSourceSession.fromUrls(request.urls)
        : MediaSourceSession.fromAsset(request.mediaAsset!);
    await _initialize(
      generation,
      resumeAt: resumeAt,
      resumePlaying: startPlaying,
    );
  }

  Future<void> _initialize(
    int generation, {
    required Duration resumeAt,
    bool resumePlaying = false,
  }) async {
    final request = state.request;
    final session = _sourceSession;
    if (request == null || session == null) return;

    await _loadPlaybackManifest(session, generation);
    while (generation == _generation) {
      var source = session.current;
      if (source == null) {
        state = state.copyWith(
          loading: false,
          initialized: false,
          failure: state.failure ?? MediaFailureKind.unavailable,
        );
        return;
      }

      if (session.currentSignatureExpired()) {
        final refreshed = await _refreshExpiredManifest(session, generation);
        if (generation != _generation) return;
        if (refreshed) {
          source = session.current;
          if (source == null) continue;
        } else if (session.moveNext()) {
          continue;
        } else {
          state = state.copyWith(
            loading: false,
            initialized: false,
            failure: MediaFailureKind.signatureExpired,
          );
          return;
        }
      }

      VideoPlayerController? candidate;
      try {
        candidate = VideoPlayerController.networkUrl(Uri.parse(source.url));
        await candidate.initialize();
        if (generation != _generation) {
          await candidate.dispose();
          return;
        }
        final duration = candidate.value.duration;
        final targetPosition = _pendingSeekPosition ?? resumeAt;
        if (targetPosition > Duration.zero && duration > Duration.zero) {
          await candidate.seekTo(
            targetPosition < duration ? targetPosition : duration,
          );
        }
        if (_pendingSeekPosition == targetPosition) {
          _pendingSeekPosition = null;
        }
        await candidate.setPlaybackSpeed(state.playbackSpeed);
        if (resumePlaying && !_sleepTimerElapsedDuringLoad) {
          await candidate.play();
          if (_sleepTimerElapsedDuringLoad) await candidate.pause();
        }
        _sleepTimerElapsedDuringLoad = false;
        _videoController = candidate;
        candidate.addListener(_onPlaybackValueChanged);
        state = state.copyWith(
          loading: false,
          initialized: true,
          failure: null,
        );
        unawaited(_persistSession());
        return;
      } catch (error) {
        await candidate?.dispose();
        if (generation != _generation) return;
        final failure = classifyMediaFailure(error, source);
        if (failure == MediaFailureKind.signatureExpired &&
            await _refreshExpiredManifest(session, generation)) {
          continue;
        }
        if (failure == MediaFailureKind.localMissing) {
          _reportMissing(session, source);
        }
        state = state.copyWith(failure: failure);
        if (!session.moveNext()) {
          state = state.copyWith(loading: false, initialized: false);
          return;
        }
      }
    }
  }

  Future<void> _loadPlaybackManifest(
    MediaSourceSession session,
    int generation,
  ) async {
    final asset = session.asset;
    if (asset == null || asset.purpose == MediaPurpose.playback) return;
    try {
      final refreshed = await refreshMediaManifest(
        ref.read(apiClientProvider),
        assetId: asset.id,
        purpose: MediaPurpose.playback,
      );
      if (generation == _generation) session.replaceManifest(refreshed);
    } catch (_) {
      // Detail candidates remain valid when only the purpose refresh fails.
    }
  }

  Future<bool> _refreshExpiredManifest(
    MediaSourceSession session,
    int generation,
  ) async {
    final asset = session.asset;
    if (asset == null || session.automaticRefreshAttempted) return false;
    session.markAutomaticRefreshAttempted();
    try {
      final refreshed = await refreshMediaManifest(
        ref.read(apiClientProvider),
        assetId: asset.id,
        purpose: MediaPurpose.playback,
      );
      if (generation != _generation) return false;
      session.replaceManifest(refreshed);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onPlaybackValueChanged() {
    final controller = _videoController;
    if (controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      if (_handlingRuntimeFailure) return;
      _handlingRuntimeFailure = true;
      unawaited(_recoverFromRuntimeFailure(controller));
      return;
    }
    _persistProgressIfDue();
    if (!_advancingQueue &&
        state.queue.isNotEmpty &&
        value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _advancingQueue = true;
      unawaited(_playNextAfterCompletion(controller));
    }
  }

  Future<void> _playNextAfterCompletion(
    VideoPlayerController completedController,
  ) async {
    if (_videoController != completedController) {
      _advancingQueue = false;
      return;
    }
    try {
      await playNext();
    } finally {
      _advancingQueue = false;
    }
  }

  Future<void> _recoverFromRuntimeFailure(
    VideoPlayerController failedController,
  ) async {
    final session = _sourceSession;
    if (session == null) return;
    final resumeAt = failedController.value.position;
    final resumePlaying = failedController.value.isPlaying;
    final generation = ++_generation;
    failedController.removeListener(_onPlaybackValueChanged);
    _videoController = null;
    await failedController.dispose();
    _handlingRuntimeFailure = false;

    if (!session.currentSignatureExpired() && !session.moveNext()) {
      state = state.copyWith(
        loading: false,
        initialized: false,
        failure: MediaFailureKind.unavailable,
      );
      return;
    }
    state = state.copyWith(loading: true, initialized: false, failure: null);
    await _initialize(
      generation,
      resumeAt: resumeAt,
      resumePlaying: resumePlaying,
    );
  }

  void _reportMissing(MediaSourceSession session, MediaSource source) {
    final asset = session.asset;
    final variantId = source.variantId;
    if (asset == null || variantId == null) return;
    unawaited(
      reportLocalMediaFailure(
        ref.read(apiClientProvider),
        assetId: asset.id,
        variantId: variantId,
        errorCode: 'media_blob_missing',
      ).catchError((_) {}),
    );
  }

  /// Chromium pauses a video when its platform view leaves the DOM. A view
  /// handoff must preserve the session, while explicit pause/close still wins.
  Future<void> preservePlaybackOnViewRemoval(
    Future<Object?> viewRemoved,
  ) async {
    if (!kIsWeb) return;
    final player = _videoController;
    if (player == null || !player.value.isPlaying) return;
    final intent = _playbackIntentVersion;
    await viewRemoved;
    await WidgetsBinding.instance.endOfFrame;
    // DOM removal queues the media pause event after the rendering frame.
    await Future<void>.delayed(Duration.zero);
    if (_videoController != player || intent != _playbackIntentVersion) return;
    final value = player.value;
    if (!value.isPlaying && !value.hasError && !value.isCompleted) {
      await player.play();
    }
  }

  Future<void> togglePlayback() async {
    _playbackIntentVersion++;
    final player = _videoController;
    if (player == null || !player.value.isInitialized) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      _sleepTimerElapsedDuringLoad = false;
      await player.play();
    }
    await _persistSession();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    if (!supportedPlaybackSpeeds.contains(speed)) {
      throw ArgumentError.value(speed, 'speed', 'unsupported playback speed');
    }
    state = state.copyWith(playbackSpeed: speed);
    final player = _videoController;
    if (player != null && player.value.isInitialized) {
      await player.setPlaybackSpeed(speed);
    }
    await _persistSession();
  }

  void setVideoAudioOnly(bool enabled) {
    if (state.request?.audioOnly != false) return;
    state = state.copyWith(videoAudioOnly: enabled);
    unawaited(_persistSession());
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerElapsedDuringLoad = false;
    if (duration == null || duration <= Duration.zero) {
      state = state.copyWith(sleepTimerEndsAt: null);
      return;
    }
    final endsAt = DateTime.now().add(duration);
    state = state.copyWith(sleepTimerEndsAt: endsAt);
    _sleepTimer = Timer(duration, () {
      unawaited(_stopForSleepTimer());
    });
  }

  Future<void> _stopForSleepTimer() async {
    _playbackIntentVersion++;
    _sleepTimer = null;
    final player = _videoController;
    if (player == null || !player.value.isInitialized) {
      _sleepTimerElapsedDuringLoad = true;
    } else {
      await player.pause();
      _sleepTimerElapsedDuringLoad = false;
    }
    state = state.copyWith(sleepTimerEndsAt: null);
  }

  bool enqueue(PlaybackRequest request) {
    if (state.request?.identity == request.identity ||
        state.queue.any((queued) => queued.identity == request.identity)) {
      return false;
    }
    state = state.copyWith(queue: [...state.queue, request]);
    unawaited(_persistSession());
    return true;
  }

  Future<void> playNext() async {
    if (state.queue.isEmpty) return;
    await activate(state.queue.first, startPlaying: true);
  }

  Future<void> playQueued(String identity) async {
    final request = state.queue
        .where((queued) => queued.identity == identity)
        .firstOrNull;
    if (request != null) await activate(request);
  }

  void removeQueued(String identity) {
    state = state.copyWith(
      queue: state.queue
          .where((queued) => queued.identity != identity)
          .toList(growable: false),
    );
    unawaited(_persistSession());
  }

  void moveQueued(String identity, int offset) {
    final queue = state.queue.toList();
    final from = queue.indexWhere((queued) => queued.identity == identity);
    if (from < 0) return;
    final to = from + offset;
    if (to < 0 || to >= queue.length) return;
    final request = queue.removeAt(from);
    queue.insert(to, request);
    state = state.copyWith(queue: List.unmodifiable(queue));
    unawaited(_persistSession());
  }

  Future<void> seekTo(Duration position) async {
    final player = _videoController;
    if (player == null || !player.value.isInitialized) return;
    final duration = player.value.duration;
    final target = duration > Duration.zero && position > duration
        ? duration
        : position;
    await player.seekTo(target < Duration.zero ? Duration.zero : target);
    await _persistSession();
  }

  Future<void> retry() async {
    final session = _sourceSession;
    if (session == null || state.request == null) return;
    session.resetForManualRetry();
    final old = _videoController;
    _videoController = null;
    if (old != null) {
      old.removeListener(_onPlaybackValueChanged);
      await old.dispose();
    }
    final generation = ++_generation;
    _pendingSeekPosition = null;
    state = state.copyWith(loading: true, initialized: false, failure: null);
    await _initialize(generation, resumeAt: Duration.zero);
  }

  Future<void> close() async {
    _generation += 1;
    final player = _videoController;
    _videoController = null;
    _sourceSession = null;
    _pendingSeekPosition = null;
    _advancingQueue = false;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _lastProgressPersistedAt = null;
    _sleepTimerElapsedDuringLoad = false;
    if (player != null) {
      player.removeListener(_onPlaybackValueChanged);
      await player.dispose();
    }
    state = const GlobalPlaybackState();
    await _removePersistedSession();
  }

  Future<void> _restorePersistedSession() async {
    if (_restoringSnapshot) return;
    _restoringSnapshot = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(playbackSessionStorageKey);
      if (raw == null || state.request != null || _generation != 0) return;
      final snapshot = PlaybackSessionSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      state = state.copyWith(
        queue: snapshot.queue,
        playbackSpeed: snapshot.playbackSpeed,
        videoAudioOnly: snapshot.videoAudioOnly,
      );
      await activate(
        snapshot.request,
        initialPosition: snapshot.position,
        startPlaying: false,
      );
    } catch (_) {
      await _removePersistedSession();
    } finally {
      _restoringSnapshot = false;
      if (state.request != null) unawaited(_persistSession());
    }
  }

  void _persistProgressIfDue() {
    final now = DateTime.now();
    if (_lastProgressPersistedAt != null &&
        now.difference(_lastProgressPersistedAt!) <
            const Duration(seconds: 5)) {
      return;
    }
    _lastProgressPersistedAt = now;
    unawaited(_persistSession());
  }

  Future<void> _persistSession() async {
    if (_restoringSnapshot) return;
    final request = state.request;
    if (request == null) return;
    final revision = ++_persistRevision;
    final snapshot = PlaybackSessionSnapshot(
      request: request,
      queue: state.queue,
      position: _pendingSeekPosition ?? currentPosition,
      playbackSpeed: state.playbackSpeed,
      videoAudioOnly: state.videoAudioOnly,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _persistRevision) return;
      await prefs.setString(
        playbackSessionStorageKey,
        jsonEncode(snapshot.toJson()),
      );
    } catch (_) {
      // Playback must remain usable when local preference storage is unavailable.
    }
  }

  Future<void> _removePersistedSession() async {
    final revision = ++_persistRevision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (revision != _persistRevision) return;
      await prefs.remove(playbackSessionStorageKey);
    } catch (_) {
      // Closing the in-memory session still succeeds if storage is unavailable.
    }
  }
}
