import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

import '../../../../theme/design_tokens.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final Map<String, String>? headers;
  final bool audioOnly;

  const VideoPlayerWidget({
    super.key,
    required this.videoUrl,
    this.headers,
    this.audioOnly = false,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        httpHeaders: widget.headers ?? {},
      );

      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: false,
        looping: !widget.audioOnly,
        aspectRatio: widget.audioOnly
            ? 16 / 3
            : _videoPlayerController.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
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
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: AppShape.cardBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _videoPlayerController,
            builder: (context, value, _) => Row(
              children: [
                IconButton.filledTonal(
                  tooltip: value.isPlaying ? '暂停' : '播放',
                  onPressed: () => value.isPlaying
                      ? _videoPlayerController.pause()
                      : _videoPlayerController.play(),
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: VideoProgressIndicator(
                    _videoPlayerController,
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
      aspectRatio: _videoPlayerController.value.aspectRatio,
      child: Chewie(controller: _chewieController!),
    );
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${value.inHours > 0 ? '${value.inHours}:' : ''}$minutes:$seconds';
  }
}
