import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import 'global_playback_controller.dart';

/// Android's media session is a control surface for the existing player.
/// It never opens media URLs or owns a second decoder.
class AndroidMediaSession extends BaseAudioHandler with SeekHandler {
  AndroidMediaSession(this._container) {
    _subscription = _container.listen(globalPlaybackProvider, (_, next) {
      _synchronize(next);
    }, fireImmediately: true);
  }

  final ProviderContainer _container;
  late final ProviderSubscription<GlobalPlaybackState> _subscription;
  StreamSubscription<void>? _noisySubscription;
  VideoPlayerController? _player;

  GlobalPlaybackController get _actions =>
      _container.read(globalPlaybackProvider.notifier);

  Future<void> listenForAudioRouteChanges() async {
    final session = await AudioSession.instance;
    // ExoPlayer already owns audio focus. Only handle the unplugged-output
    // event here; requesting a second focus lease would compete with it.
    _noisySubscription = session.becomingNoisyEventStream.listen((_) {
      unawaited(_actions.pause());
    });
  }

  MediaItem _item(PlaybackRequest request, {Duration? duration}) => MediaItem(
    // Resource URLs (including signed ones) must not enter system metadata.
    id: '${request.contentId}:${request.mediaAsset?.id ?? 'primary'}:${request.audioOnly}',
    title: request.title,
    album: 'VaultStream',
    duration: duration,
  );

  void _synchronize(GlobalPlaybackState state) {
    final player = _actions.videoController;
    if (_player != player) {
      _player?.removeListener(_onPlayerChanged);
      _player = player;
      player?.addListener(_onPlayerChanged);
    }
    final request = state.request;
    final current = request == null
        ? null
        : _item(request, duration: player?.value.duration);
    mediaItem.add(current);
    queue.add([?current, ...state.queue.map(_item)]);
    _publish(force: true);
  }

  void _onPlayerChanged() => _publish();

  void _publish({bool force = false}) {
    final state = _container.read(globalPlaybackProvider);
    final value = _player?.value;
    final processing = state.request == null
        ? AudioProcessingState.idle
        : state.loading
        ? AudioProcessingState.loading
        : state.failure != null
        ? AudioProcessingState.error
        : value?.isCompleted == true
        ? AudioProcessingState.completed
        : value?.isBuffering == true
        ? AudioProcessingState.buffering
        : state.initialized
        ? AudioProcessingState.ready
        : AudioProcessingState.loading;
    final playing = value?.isPlaying ?? false;
    final position = value?.position ?? Duration.zero;
    final previous = playbackState.value;
    if (!force &&
        previous.processingState == processing &&
        previous.playing == playing &&
        previous.speed == state.playbackSpeed &&
        (previous.position - position).abs() <
            const Duration(milliseconds: 500)) {
      return;
    }
    playbackState.add(
      PlaybackState(
        processingState: processing,
        playing: playing,
        controls: state.request == null
            ? const []
            : [
                if (state.initialized)
                  playing ? MediaControl.pause : MediaControl.play,
                if (state.queue.isNotEmpty) MediaControl.skipToNext,
                MediaControl.stop,
              ],
        systemActions: state.initialized
            ? const {
                MediaAction.seek,
                MediaAction.seekForward,
                MediaAction.seekBackward,
                MediaAction.setSpeed,
              }
            : const {},
        updatePosition: position,
        bufferedPosition: value?.buffered.lastOrNull?.end ?? Duration.zero,
        speed: state.playbackSpeed,
        queueIndex: state.request == null ? null : 0,
        errorCode: state.failure == null ? null : 1,
        errorMessage: state.failure == null ? null : '媒体暂时无法播放，请在应用内重试',
      ),
    );
  }

  @override
  Future<void> play() => _actions.play();
  @override
  Future<void> pause() => _actions.pause();
  @override
  Future<void> stop() => _actions.close();
  @override
  Future<void> seek(Duration position) => _actions.seekTo(position);
  @override
  Future<void> setSpeed(double speed) => _actions.setPlaybackSpeed(speed);
  @override
  Future<void> skipToNext() => _actions.playNext();
  @override
  Future<void> skipToQueueItem(int index) async {
    if (index == 0) {
      await seek(Duration.zero);
      await play();
      return;
    }
    final pending = _container.read(globalPlaybackProvider).queue;
    if (index > 0 && index <= pending.length) {
      await _actions.playQueued(pending[index - 1].identity);
    }
  }

  void dispose() {
    _subscription.close();
    _player?.removeListener(_onPlayerChanged);
    unawaited(_noisySubscription?.cancel());
  }
}
