import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../theme/design_tokens.dart';
import 'global_playback_controller.dart';
import 'android_picture_in_picture.dart';
import 'global_player_widgets.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  final _surfaceKey = GlobalKey();
  final _detailsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalPlaybackProvider);
    final request = state.request;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        toolbarHeight: WindowMetrics.of(context).heightClass.isCompact
            ? 48
            : null,
        title: const Text('当前播放'),
        actions: [
          if (ref.watch(pictureInPictureProvider).supported &&
              request?.audioOnly == false &&
              !state.videoAudioOnly &&
              state.initialized)
            IconButton(
              tooltip: '画中画',
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
              onPressed: () async {
                final entered = await ref
                    .read(pictureInPictureProvider.notifier)
                    .enter();
                if (!entered && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('无法进入画中画')));
                }
              },
            ),
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
      body: SafeArea(
        top: false,
        child: request == null
            ? const _EmptyPlayer()
            : LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = WindowMetrics.fromSize(constraints.biggest);
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  final paneWidth = constraints.maxWidth - AppSpacing.md * 3;
                  final audioPresentation =
                      request.audioOnly || state.videoAudioOnly;
                  final sideBySide =
                      !audioPresentation &&
                      metrics.widthClass.atLeast(WindowWidthClass.medium) &&
                      paneWidth >= 560 &&
                      (metrics.isShortLandscape ||
                          metrics.supportsSupportingPane);
                  // Large text scrolls in the details pane instead of forcing
                  // short landscape screens into a cramped vertical layout.
                  final sideWidth = sideBySide
                      ? (AppPane.supportingWidth * textScale).clamp(
                          280.0,
                          paneWidth / 2,
                        )
                      : 0.0;
                  final player = GlobalPlaybackSurface(
                    key: _surfaceKey,
                    request: request,
                    activateOnMount: false,
                  );
                  final audioHeader = ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: player,
                    ),
                  );
                  final details = DragBoundary(
                    key: _detailsKey,
                    // Keep an edge gutter for auto-scroll inside the drag boundary.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: CustomScrollView(
                        slivers: [
                          if (audioPresentation)
                            if (metrics.heightClass.isCompact)
                              SliverToBoxAdapter(child: audioHeader)
                            else
                              PinnedHeaderSliver(child: audioHeader),
                          SliverList.list(
                            children: [
                              _PlaybackDetails(request: request),
                              const SizedBox(height: AppSpacing.sm),
                              const PlaybackSessionControls(),
                              const SizedBox(height: AppSpacing.md),
                              PlaybackSegmentList(request: request),
                              const SizedBox(height: AppSpacing.md),
                              PlaybackBookmarkPanel(request: request),
                              const SizedBox(height: AppSpacing.md),
                            ],
                          ),
                          const PlaybackQueueSliver(),
                        ],
                      ),
                    ),
                  );
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: sideBySide
                            ? double.infinity
                            : AppPane.readableMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: audioPresentation
                            ? details
                            : Flex(
                                direction: sideBySide
                                    ? Axis.horizontal
                                    : Axis.vertical,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (sideBySide)
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.topCenter,
                                        child: player,
                                      ),
                                    )
                                  else
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: constraints.maxHeight * 0.45,
                                      ),
                                      child: player,
                                    ),
                                  const SizedBox(
                                    width: AppSpacing.md,
                                    height: AppSpacing.md,
                                  ),
                                  if (sideBySide)
                                    SizedBox(width: sideWidth, child: details)
                                  else
                                    Expanded(child: details),
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _PlaybackDetails extends StatelessWidget {
  const _PlaybackDetails({required this.request});

  final PlaybackRequest request;

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
