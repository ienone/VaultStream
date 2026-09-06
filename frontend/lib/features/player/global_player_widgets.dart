import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/media/media_segment.dart';
import '../../core/media/media_source_session.dart';
import '../../core/network/api_client.dart';
import '../../theme/design_tokens.dart';
import 'global_playback_controller.dart';
import 'media_bookmark.dart';
import 'media_bookmark_provider.dart';

class GlobalPlaybackChrome extends StatelessWidget {
  const GlobalPlaybackChrome({
    super.key,
    required this.child,
    this.showMiniPlayer = true,
  });

  final Widget child;
  final bool showMiniPlayer;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: child),
      if (showMiniPlayer) const GlobalMiniPlayer(),
    ],
  );
}

class GlobalPlaybackSurface extends ConsumerStatefulWidget {
  const GlobalPlaybackSurface({
    super.key,
    required this.request,
    this.initialPosition,
    this.activateOnMount = true,
  });

  final PlaybackRequest request;
  final Duration? initialPosition;
  final bool activateOnMount;

  @override
  ConsumerState<GlobalPlaybackSurface> createState() =>
      _GlobalPlaybackSurfaceState();
}

class _GlobalPlaybackSurfaceState extends ConsumerState<GlobalPlaybackSurface> {
  bool _activationScheduled = false;

  bool _shouldActivate(PlaybackRequest request) {
    final active = ref.read(globalPlaybackProvider).request;
    return active == null || active.identity == request.identity;
  }

  void _scheduleActivation() {
    if (!widget.activateOnMount) return;
    if (_activationScheduled) return;
    _activationScheduled = true;
    Future<void>.microtask(() async {
      try {
        if (!mounted || !_shouldActivate(widget.request)) return;
        await ref
            .read(globalPlaybackProvider.notifier)
            .activate(widget.request, initialPosition: widget.initialPosition);
      } finally {
        _activationScheduled = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleActivation();
  }

  @override
  void didUpdateWidget(covariant GlobalPlaybackSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.identity != widget.request.identity ||
        oldWidget.initialPosition != widget.initialPosition) {
      _scheduleActivation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(globalPlaybackProvider);
    final controller = ref.read(globalPlaybackProvider.notifier);
    final failure = state.failure;
    final active = state.request?.identity == widget.request.identity;
    final audioPresentation =
        widget.request.audioOnly || (active && state.videoAudioOnly);
    if (!active && state.request == null) _scheduleActivation();
    if (!active && (state.request != null || !widget.activateOnMount)) {
      return _InactivePlaybackChoice(
        activeRequest: state.request,
        requested: widget.request,
        initialPosition: widget.initialPosition,
        queued: state.queue.any(
          (queued) => queued.identity == widget.request.identity,
        ),
      );
    }
    if (!active || state.loading) {
      return _PlayerFrame(
        audioOnly: audioPresentation,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (failure != null) {
      return _PlayerFrame(
        audioOnly: audioPresentation,
        child: _FailureView(
          label: mediaFailureLabel(
            failure,
            audioOnly: widget.request.audioOnly,
          ),
          onRetry: controller.retry,
        ),
      );
    }
    final player = controller.videoController;
    if (!state.initialized || player == null) {
      return _PlayerFrame(
        audioOnly: audioPresentation,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (audioPresentation) {
      return _AudioControls(
        controller: player,
        videoAudioOnly: !widget.request.audioOnly,
      );
    }
    return _VideoSurface(controller: player);
  }
}

class _InactivePlaybackChoice extends ConsumerWidget {
  const _InactivePlaybackChoice({
    required this.activeRequest,
    required this.requested,
    required this.initialPosition,
    required this.queued,
  });

  final PlaybackRequest? activeRequest;
  final PlaybackRequest requested;
  final Duration? initialPosition;
  final bool queued;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(globalPlaybackProvider.notifier);
    return _PlayerFrame(
      audioOnly: requested.audioOnly,
      height: 176,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (activeRequest != null)
              Text(
                '当前媒体：${activeRequest!.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: () => actions.activate(
                    requested,
                    initialPosition: initialPosition,
                    startPlaying: true,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('立即播放'),
                ),
                if (activeRequest != null)
                  OutlinedButton.icon(
                    onPressed: queued ? null : () => actions.enqueue(requested),
                    icon: Icon(
                      queued ? Icons.check_rounded : Icons.queue_music_rounded,
                    ),
                    label: Text(queued ? '已加入队列' : '加入队列'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackSegmentList extends ConsumerStatefulWidget {
  const PlaybackSegmentList({super.key, required this.request});

  final PlaybackRequest request;

  @override
  ConsumerState<PlaybackSegmentList> createState() =>
      _PlaybackSegmentListState();
}

class PlaybackQueuePanel extends ConsumerWidget {
  const PlaybackQueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      globalPlaybackProvider.select((state) => state.queue),
    );
    if (queue.isEmpty) return const SizedBox.shrink();
    final actions = ref.read(globalPlaybackProvider.notifier);
    return Card(
      key: const ValueKey('playback-queue'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.queue_music_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '接下来',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${queue.length} 条'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: queue.length,
              onReorderItem: (oldIndex, newIndex) {
                actions.moveQueued(
                  queue[oldIndex].identity,
                  newIndex - oldIndex,
                );
              },
              itemBuilder: (context, index) {
                final request = queue[index];
                return ListTile(
                  key: ValueKey('queued-${request.identity}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    request.audioOnly
                        ? Icons.headphones_rounded
                        : Icons.smart_display_rounded,
                  ),
                  title: Text(
                    request.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(request.audioOnly ? '音频' : '视频'),
                  onTap: () => actions.playQueued(request.identity),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '立即播放 ${request.title}',
                        onPressed: () => actions.playQueued(request.identity),
                        icon: const Icon(Icons.play_arrow_rounded),
                      ),
                      IconButton(
                        tooltip: '从队列移除 ${request.title}',
                        onPressed: () => actions.removeQueued(request.identity),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackSessionControls extends ConsumerWidget {
  const PlaybackSessionControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(globalPlaybackProvider);
    final actions = ref.read(globalPlaybackProvider.notifier);
    final timerEndsAt = state.sleepTimerEndsAt;
    return Card(
      key: const ValueKey('playback-session-controls'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('播放设置', style: Theme.of(context).textTheme.titleMedium),
            if (state.request?.audioOnly == false) ...[
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile.adaptive(
                key: const ValueKey('video-audio-only-toggle'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.headphones_rounded),
                title: const Text('仅听声音'),
                value: state.videoAudioOnly,
                onChanged: actions.setVideoAudioOnly,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text('倍速', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final speed in supportedPlaybackSpeeds)
                  ChoiceChip(
                    label: Text('${_speedLabel(speed)}x'),
                    selected: state.playbackSpeed == speed,
                    onSelected: (_) {
                      unawaited(actions.setPlaybackSpeed(speed));
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    timerEndsAt == null
                        ? '定时停止'
                        : '将在 ${_clockTime(timerEndsAt)} 停止',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (timerEndsAt != null)
                  TextButton(
                    onPressed: () => actions.setSleepTimer(null),
                    child: const Text('取消'),
                  ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final minutes in const [15, 30, 60])
                  ActionChip(
                    avatar: const Icon(Icons.bedtime_outlined, size: 18),
                    label: Text('$minutes 分钟'),
                    onPressed: () =>
                        actions.setSleepTimer(Duration(minutes: minutes)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class PlaybackBookmarkPanel extends ConsumerWidget {
  const PlaybackBookmarkPanel({super.key, required this.request});

  final PlaybackRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = request.mediaAsset;
    if (asset == null) return const SizedBox.shrink();
    final query = (contentId: request.contentId, mediaAssetId: asset.id);
    final bookmarks = ref.watch(mediaBookmarksProvider(query));
    final playback = ref.read(globalPlaybackProvider.notifier);

    return Card(
      key: const ValueKey('playback-bookmarks'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bookmarks_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '时间点书签',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _createBookmark(
                    context,
                    ref,
                    query,
                    playback.currentPosition,
                  ),
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('记录当前时间点'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            bookmarks.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Row(
                children: [
                  Expanded(
                    child: Text(
                      formatApiErrorMessage(
                        error,
                        fallbackMessage: '时间点书签加载失败',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(mediaBookmarksProvider(query)),
                    child: const Text('重试'),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        '播放到需要回看的位置时记录书签，可附加一条笔记。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : Column(
                      children: [
                        for (final bookmark in items)
                          ListTile(
                            key: ValueKey('media-bookmark-${bookmark.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: Text(
                              _duration(bookmark.position),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            title: Text(
                              bookmark.note?.trim().isNotEmpty == true
                                  ? bookmark.note!.trim()
                                  : '无笔记',
                            ),
                            onTap: () => playback.activate(
                              request,
                              initialPosition: bookmark.position,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: '编辑书签笔记',
                                  onPressed: () => _updateBookmark(
                                    context,
                                    ref,
                                    query,
                                    bookmark,
                                  ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: '删除时间点书签',
                                  onPressed: () => _deleteBookmark(
                                    context,
                                    ref,
                                    query,
                                    bookmark,
                                  ),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createBookmark(
    BuildContext context,
    WidgetRef ref,
    MediaBookmarkQuery query,
    Duration position,
  ) async {
    final result = await _showBookmarkDialog(
      context,
      title: '记录 ${_duration(position)}',
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(mediaBookmarkActionsProvider)
          .create(query: query, position: position, note: result.note);
    } catch (error) {
      if (context.mounted) _showBookmarkError(context, error);
    }
  }

  Future<void> _updateBookmark(
    BuildContext context,
    WidgetRef ref,
    MediaBookmarkQuery query,
    MediaBookmark bookmark,
  ) async {
    final result = await _showBookmarkDialog(
      context,
      title: '编辑 ${_duration(bookmark.position)}',
      initialNote: bookmark.note,
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(mediaBookmarkActionsProvider)
          .updateNote(query: query, bookmarkId: bookmark.id, note: result.note);
    } catch (error) {
      if (context.mounted) _showBookmarkError(context, error);
    }
  }

  Future<void> _deleteBookmark(
    BuildContext context,
    WidgetRef ref,
    MediaBookmarkQuery query,
    MediaBookmark bookmark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除时间点书签？'),
        content: Text('${_duration(bookmark.position)} 的书签将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(mediaBookmarkActionsProvider)
          .delete(query: query, bookmarkId: bookmark.id);
    } catch (error) {
      if (context.mounted) _showBookmarkError(context, error);
    }
  }
}

class _BookmarkEditResult {
  const _BookmarkEditResult(this.note);

  final String? note;
}

Future<_BookmarkEditResult?> _showBookmarkDialog(
  BuildContext context, {
  required String title,
  String? initialNote,
}) => showDialog<_BookmarkEditResult>(
  context: context,
  builder: (_) => _BookmarkEditDialog(title: title, initialNote: initialNote),
);

class _BookmarkEditDialog extends StatefulWidget {
  const _BookmarkEditDialog({required this.title, this.initialNote});

  final String title;
  final String? initialNote;

  @override
  State<_BookmarkEditDialog> createState() => _BookmarkEditDialogState();
}

class _BookmarkEditDialogState extends State<_BookmarkEditDialog> {
  late final TextEditingController _noteController = TextEditingController(
    text: widget.initialNote,
  );

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _noteController,
      autofocus: true,
      maxLength: 2000,
      minLines: 2,
      maxLines: 5,
      decoration: const InputDecoration(
        labelText: '笔记（可选）',
        hintText: '为什么这个时间点值得回来？',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final note = _noteController.text.trim();
          Navigator.pop(
            context,
            _BookmarkEditResult(note.isEmpty ? null : note),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}

void _showBookmarkError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(formatApiErrorMessage(error, fallbackMessage: '时间点书签操作失败')),
    ),
  );
}

class _PlaybackSegmentListState extends ConsumerState<PlaybackSegmentList> {
  MediaSegmentType _selectedType = MediaSegmentType.chapter;

  @override
  void didUpdateWidget(covariant PlaybackSegmentList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.identity != widget.request.identity ||
        oldWidget.request.mediaAsset?.id != widget.request.mediaAsset?.id) {
      _selectedType = MediaSegmentType.chapter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _segmentsByType(widget.request);
    final chapters = grouped[MediaSegmentType.chapter] ?? const [];
    final transcripts = grouped[MediaSegmentType.transcript] ?? const [];
    if (chapters.isEmpty && transcripts.isEmpty) {
      return const SizedBox.shrink();
    }
    final availableTypes = [
      if (chapters.isNotEmpty) MediaSegmentType.chapter,
      if (transcripts.isNotEmpty) MediaSegmentType.transcript,
    ];
    final selectedType = availableTypes.contains(_selectedType)
        ? _selectedType
        : availableTypes.first;
    final segments = grouped[selectedType]!;

    final state = ref.watch(globalPlaybackProvider);
    final actions = ref.read(globalPlaybackProvider.notifier);
    final active = state.request?.identity == widget.request.identity;
    final player = active ? actions.videoController : null;
    final title = availableTypes.length > 1
        ? '章节与逐字稿'
        : selectedType == MediaSegmentType.chapter
        ? '章节'
        : '逐字稿';

    Widget buildList(Duration? position) {
      final selectedIndex = position == null
          ? null
          : _activeSegmentIndex(segments, position);
      final tiles = ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: segments.length <= 6,
        physics: segments.length <= 6
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: segments.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final segment = segments[index];
          return ListTile(
            key: ValueKey(
              'media-segment-${segment.mediaAssetId}-${segment.startPosition.inMilliseconds}',
            ),
            selected: index == selectedIndex,
            leading: SizedBox(
              width: 54,
              child: Text(
                _duration(segment.startPosition),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            title: Text(segment.title),
            subtitle: segment.excerpt.isEmpty
                ? null
                : Text(
                    segment.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () => actions.activate(
              widget.request,
              initialPosition: segment.startPosition,
            ),
          );
        },
      );

      return Card(
        key: const ValueKey('playback-segment-list'),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.format_list_numbered_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text('${segments.length} 段'),
                ],
              ),
            ),
            if (availableTypes.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<MediaSegmentType>(
                    segments: const [
                      ButtonSegment(
                        value: MediaSegmentType.chapter,
                        icon: Icon(Icons.format_list_numbered_rounded),
                        label: Text('章节'),
                      ),
                      ButtonSegment(
                        value: MediaSegmentType.transcript,
                        icon: Icon(Icons.subtitles_outlined),
                        label: Text('逐字稿'),
                      ),
                    ],
                    selected: {selectedType},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      setState(() => _selectedType = selection.single);
                    },
                  ),
                ),
              ),
            if (segments.length <= 6)
              tiles
            else
              SizedBox(height: 420, child: tiles),
          ],
        ),
      );
    }

    if (player == null || !player.value.isInitialized) {
      return buildList(null);
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) => buildList(value.position),
    );
  }
}

Map<MediaSegmentType, List<MediaSegment>> _segmentsByType(
  PlaybackRequest request,
) {
  final assetId = request.mediaAsset?.id;
  final sameAsset = request.segments
      .where((segment) => assetId == null || segment.mediaAssetId == assetId)
      .toList(growable: false);
  final chapters = sameAsset
      .where((segment) => segment.segmentType == MediaSegmentType.chapter)
      .toList();
  final transcripts = sameAsset
      .where((segment) => segment.segmentType == MediaSegmentType.transcript)
      .toList();
  chapters.sort((a, b) => a.startPosition.compareTo(b.startPosition));
  transcripts.sort((a, b) => a.startPosition.compareTo(b.startPosition));
  return {
    MediaSegmentType.chapter: List.unmodifiable(chapters),
    MediaSegmentType.transcript: List.unmodifiable(transcripts),
  };
}

int? _activeSegmentIndex(List<MediaSegment> segments, Duration position) {
  int? selected;
  for (var index = 0; index < segments.length; index += 1) {
    final segment = segments[index];
    if (position < segment.startPosition) break;
    final end = segment.endSeconds == null
        ? index + 1 < segments.length
              ? segments[index + 1].startPosition
              : null
        : Duration(
            milliseconds: (segment.endSeconds! * Duration.millisecondsPerSecond)
                .round(),
          );
    if (end == null || position < end) selected = index;
  }
  return selected;
}

class GlobalMiniPlayer extends ConsumerWidget {
  const GlobalMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(globalPlaybackProvider);
    final request = state.request;
    if (request == null) {
      return const SizedBox.shrink();
    }
    final actions = ref.read(globalPlaybackProvider.notifier);
    final player = actions.videoController;
    final scheme = Theme.of(context).colorScheme;
    final audioPresentation = request.audioOnly || state.videoAudioOnly;

    return Material(
      key: const ValueKey('global-mini-player'),
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: () => context.push('/player'),
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: audioPresentation || player == null
                      ? Icon(
                          audioPresentation
                              ? Icons.graphic_eq_rounded
                              : Icons.movie_outlined,
                          color: scheme.primary,
                        )
                      : AspectRatio(
                          aspectRatio: player.value.aspectRatio == 0
                              ? 16 / 9
                              : player.value.aspectRatio,
                          child: VideoPlayer(player),
                        ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.loading
                              ? '正在载入'
                              : state.failure == null
                              ? state.videoAudioOnly && !request.audioOnly
                                    ? '仅听声音 · 点击展开当前播放'
                                    : '点击展开当前播放'
                              : mediaFailureLabel(
                                  state.failure!,
                                  audioOnly: request.audioOnly,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (state.loading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (player != null && state.initialized)
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: player,
                    builder: (context, value, _) => IconButton(
                      tooltip: value.isPlaying ? '暂停' : '播放',
                      onPressed: actions.togglePlayback,
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '关闭播放器',
                  onPressed: actions.close,
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio,
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(controller),
          Align(
            alignment: Alignment.bottomCenter,
            child: ColoredBox(
              color: Colors.black54,
              child: _PlaybackControls(controller: controller),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AudioControls extends StatelessWidget {
  const _AudioControls({required this.controller, this.videoAudioOnly = false});

  final VideoPlayerController controller;
  final bool videoAudioOnly;

  @override
  Widget build(BuildContext context) => Material(
    key: videoAudioOnly ? const ValueKey('video-audio-only-surface') : null,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: AppShape.cardBorder,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (videoAudioOnly)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Icon(Icons.headphones_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('视频画面已隐藏，声音继续播放')),
              ],
            ),
          ),
        _PlaybackControls(controller: controller),
      ],
    ),
  );
}

class _PlaybackControls extends ConsumerWidget {
  const _PlaybackControls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: controller,
    builder: (context, value, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: value.isPlaying ? '暂停' : '播放',
            onPressed: ref.read(globalPlaybackProvider.notifier).togglePlayback,
            icon: Icon(
              value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(width: 8),
          Text('${_duration(value.position)} / ${_duration(value.duration)}'),
        ],
      ),
    ),
  );
}

class _PlayerFrame extends StatelessWidget {
  const _PlayerFrame({
    required this.audioOnly,
    required this.child,
    this.height,
  });

  final bool audioOnly;
  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
    height: height ?? (audioOnly ? 88 : 240),
    color: audioOnly
        ? Theme.of(context).colorScheme.surfaceContainerHigh
        : Colors.black,
    child: child,
  );
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.label, required this.onRetry});

  final String label;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline),
        const SizedBox(height: 8),
        Text(label),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      ],
    ),
  );
}

String _duration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${value.inHours > 0 ? '${value.inHours}:' : ''}$minutes:$seconds';
}

String _speedLabel(double speed) => speed == speed.roundToDouble()
    ? speed.toStringAsFixed(0)
    : speed.toString();

String _clockTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
