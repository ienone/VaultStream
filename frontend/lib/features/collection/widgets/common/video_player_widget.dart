import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../../../../core/media/media_candidate_resolver.dart';
import '../../../../theme/design_tokens.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final List<String> fallbackUrls;
  final Map<String, String>? headers;
  final bool audioOnly;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.fallbackUrls = const [],
    this.headers,
    this.audioOnly = false,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _initialized = false;
  String? _error;
  int _initializationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.fallbackUrls != widget.fallbackUrls) {
      _disposeControllers();
      _initialized = false;
      _error = null;
      _initializePlayer();
    }
  }

  Future<void> _initializePlayer() async {
    final generation = ++_initializationGeneration;
    final resolver = MediaCandidateResolver([
      widget.videoUrl,
      ...widget.fallbackUrls,
    ]);
    while (mounted &&
        generation == _initializationGeneration &&
        resolver.current != null) {
      VideoPlayerController? candidate;
      try {
        candidate = VideoPlayerController.networkUrl(
          Uri.parse(resolver.current!),
          httpHeaders: resolver.index == 0 ? widget.headers ?? {} : const {},
        );

        await candidate.initialize();
        if (!mounted || generation != _initializationGeneration) {
          await candidate.dispose();
          return;
        }
        _videoPlayerController = candidate;

        _chewieController = ChewieController(
          videoPlayerController: candidate,
          autoPlay: false,
          looping: !widget.audioOnly,
          aspectRatio: widget.audioOnly ? 16 / 3 : candidate.value.aspectRatio,
          errorBuilder: (context, errorMessage) {
            return Center(
              child: Text(
                errorMessage,
                style: const TextStyle(color: Colors.white),
              ),
            );
          },
        );

        setState(() {
          _initialized = true;
        });
        return;
      } catch (error) {
        await candidate?.dispose();
        if (!mounted || generation != _initializationGeneration) return;
        if (!resolver.moveNext()) {
          if (mounted) setState(() => _error = error.toString());
          return;
        }
      }
    }
  }

  void _disposeControllers() {
    _chewieController?.dispose();
    _chewieController = null;
    _videoPlayerController?.dispose();
    _videoPlayerController = null;
  }

  @override
  void dispose() {
    _initializationGeneration += 1;
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.black,
        height: widget.audioOnly ? 88 : 240,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(height: 8),
              Text(
                widget.audioOnly ? '音频加载失败' : '视频加载失败',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized || _chewieController == null) {
      return Container(
        color: Colors.black,
        height: widget.audioOnly ? 88 : 240,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (widget.audioOnly) {
      final videoPlayerController = _videoPlayerController!;
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: AppShape.cardBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: videoPlayerController,
            builder: (context, value, _) => Row(
              children: [
                IconButton.filledTonal(
                  tooltip: value.isPlaying ? '暂停' : '播放',
                  onPressed: () => value.isPlaying
                      ? videoPlayerController.pause()
                      : videoPlayerController.play(),
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: VideoProgressIndicator(
                    videoPlayerController,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_formatDuration(value.position)),
              ],
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: _videoPlayerController!.value.aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${value.inHours > 0 ? '${value.inHours}:' : ''}$minutes:$seconds';
  }
}
