import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/design_tokens.dart';
import 'global_playback_controller.dart';
import 'global_player_widgets.dart';

class PlayerPage extends ConsumerWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(globalPlaybackProvider);
    final request = state.request;
    return Scaffold(
      appBar: AppBar(
        title: const Text('当前播放'),
        actions: [
          if (request != null)
            IconButton(
              tooltip: '关闭播放器',
              onPressed: () async {
                await ref.read(globalPlaybackProvider.notifier).close();
                if (context.mounted && context.canPop()) context.pop();
              },
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      body: request == null
          ? const _EmptyPlayer()
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide =
                    constraints.maxWidth >= 840 &&
                    constraints.maxHeight >= 520 &&
                    !request.audioOnly &&
                    !state.videoAudioOnly;
                final player = GlobalPlaybackSurface(request: request);
                final details = _PlaybackDetails(
                  request: request,
                  videoAudioOnly: state.videoAudioOnly,
                );
                const controls = PlaybackSessionControls();
                final segments = PlaybackSegmentList(request: request);
                final bookmarks = PlaybackBookmarkPanel(request: request);
                const queue = PlaybackQueuePanel();
                if (wide) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: player),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                          child: ListView(
                            children: [
                              details,
                              const SizedBox(height: AppSpacing.md),
                              segments,
                              const SizedBox(height: AppSpacing.md),
                              bookmarks,
                              const SizedBox(height: AppSpacing.md),
                              controls,
                              const SizedBox(height: AppSpacing.md),
                              queue,
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppPane.readableMaxWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        details,
                        const SizedBox(height: AppSpacing.md),
                        player,
                        const SizedBox(height: AppSpacing.md),
                        segments,
                        const SizedBox(height: AppSpacing.md),
                        bookmarks,
                        const SizedBox(height: AppSpacing.md),
                        controls,
                        const SizedBox(height: AppSpacing.md),
                        queue,
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PlaybackDetails extends StatelessWidget {
  const _PlaybackDetails({required this.request, required this.videoAudioOnly});

  final PlaybackRequest request;
  final bool videoAudioOnly;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(request.title, style: Theme.of(context).textTheme.titleLarge),
      TextButton(
        onPressed: () => context.push('/collection/${request.contentId}'),
        child: const Text('返回内容详情'),
      ),
    ],
  );
}

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_circle_outline_rounded, size: 48),
        SizedBox(height: 12),
        Text('当前没有播放内容'),
      ],
    ),
  );
}
