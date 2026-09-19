import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/media/media_segment.dart';
import '../../core/media/media_source_session.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/browser_leave_guard.dart';
import '../../core/widgets/adaptive_form_dialog.dart';
import '../../core/widgets/predictive_back_dialog.dart';
import '../../core/widgets/discard_changes_dialog.dart';
import '../../theme/design_tokens.dart';
import 'global_playback_controller.dart';
import 'android_picture_in_picture.dart';
import 'media_bookmark.dart';
import 'media_bookmark_provider.dart';
import 'playback_route_observer.dart';

class GlobalPlaybackChrome extends StatelessWidget {
  const GlobalPlaybackChrome({
    super.key,
    required this.child,
    this.showMiniPlayer = true,
  });

  final Widget child;
  final bool showMiniPlayer;

  @override
  Widget build(BuildContext context) => _PlaybackPage(
    route: ModalRoute.of(context),
    child: Column(
      children: [
        Expanded(child: child),
        if (showMiniPlayer)
          Offstage(
            offstage: MediaQuery.viewInsetsOf(context).bottom > 0,
            child: const GlobalMiniPlayer(),
          ),
      ],
    ),
  );
}

/// 子 Navigator 内的阅读器也必须在根级播放器页面打开时交出视频视图。
class _PlaybackPage extends InheritedWidget {
  const _PlaybackPage({required this.route, required super.child});
  final Route<dynamic>? route;

  @override
  bool updateShouldNotify(_PlaybackPage oldWidget) => route != oldWidget.route;
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
      return _AudioControls(controller: player);
    }
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: _VideoSurface(controller: player),
    );
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
      minHeight: 0,
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

class PlaybackQueueSliver extends ConsumerWidget {
  const PlaybackQueueSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(
      globalPlaybackProvider.select((state) => state.queue),
    );
    if (queue.isEmpty) return const SliverToBoxAdapter();
    final actions = ref.read(globalPlaybackProvider.notifier);
    return SliverMainAxisGroup(
      key: const ValueKey('playback-queue'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '接下来',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${queue.length} 条'),
              ],
            ),
          ),
        ),
        SliverReorderableList(
          proxyDecorator: (child, index, animation) => Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: AppShape.cardBorder,
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          itemCount: queue.length,
          onReorderItem: (oldIndex, newIndex) {
            actions.moveQueued(queue[oldIndex].identity, newIndex - oldIndex);
          },
          itemBuilder: (context, index) {
            final request = queue[index];
            return ListTile(
              key: ValueKey('queued-${request.identity}'),
              contentPadding: EdgeInsets.zero,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.request?.audioOnly == false)
          SwitchListTile.adaptive(
            key: const ValueKey('video-audio-only-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('仅听声音'),
            value: state.videoAudioOnly,
            onChanged: actions.setVideoAudioOnly,
          ),
        Row(
          children: [
            const Expanded(child: Text('倍速')),
            Material(
              type: MaterialType.transparency,
              child: PopupMenuButton<double>(
                useRootNavigator: true,
                borderRadius: BorderRadius.circular(AppShape.pill),
                clipBehavior: Clip.antiAlias,
                popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
                    ? AnimationStyle.noAnimation
                    : null,
                tooltip: '调整播放速度',
                initialValue: state.playbackSpeed,
                itemBuilder: (_) => [
                  for (final speed in supportedPlaybackSpeeds)
                    CheckedPopupMenuItem(
                      value: speed,
                      checked: speed == state.playbackSpeed,
                      child: Text('${_speedLabel(speed)}x'),
                    ),
                ],
                onSelected: (speed) =>
                    unawaited(actions.setPlaybackSpeed(speed)),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${_speedLabel(state.playbackSpeed)}x'),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.arrow_drop_down_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('定时停止'),
          trailing: Material(
            type: MaterialType.transparency,
            child: PopupMenuButton<int>(
              useRootNavigator: true,
              borderRadius: BorderRadius.circular(AppShape.pill),
              clipBehavior: Clip.antiAlias,
              popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
                  ? AnimationStyle.noAnimation
                  : null,
              tooltip: '设置定时停止',
              onSelected: (minutes) => actions.setSleepTimer(
                minutes == 0 ? null : Duration(minutes: minutes),
              ),
              itemBuilder: (_) => [
                if (timerEndsAt != null)
                  const PopupMenuItem(value: 0, child: Text('取消定时')),
                for (final minutes in const [15, 30, 60])
                  PopupMenuItem(value: minutes, child: Text('$minutes 分钟后')),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timerEndsAt == null ? '未设置' : _clockTime(timerEndsAt),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(Icons.arrow_drop_down_rounded),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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

    return Column(
      key: const ValueKey('playback-bookmarks'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '时间点书签',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton.filledTonal(
              tooltip: '记录当前时间点',
              onPressed: () => _createBookmark(
                context,
                ref,
                query,
                playback.currentPosition,
              ),
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
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
                  formatApiErrorMessage(error, fallbackMessage: '时间点书签加载失败'),
                ),
              ),
              TextButton(
                onPressed: () => ref.invalidate(mediaBookmarksProvider(query)),
                child: const Text('重试'),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    for (final bookmark in items)
                      _PlaybackBookmarkTile(
                        key: ValueKey('media-bookmark-${bookmark.id}'),
                        time: _duration(bookmark.position),
                        note: bookmark.note,
                        onPlay: () => playback.activate(
                          request,
                          initialPosition: bookmark.position,
                        ),
                        onEdit: () =>
                            _updateBookmark(context, ref, query, bookmark),
                        onDelete: () =>
                            _deleteBookmark(context, ref, query, bookmark),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _createBookmark(
    BuildContext context,
    WidgetRef ref,
    MediaBookmarkQuery query,
    Duration position,
  ) async {
    final actions = ref.read(mediaBookmarkActionsProvider);
    await _showBookmarkDialog(
      context,
      title: '记录时间点',
      positionLabel: _duration(position),
      onSave: (note) async {
        await actions.create(query: query, position: position, note: note);
      },
    );
  }

  Future<void> _updateBookmark(
    BuildContext context,
    WidgetRef ref,
    MediaBookmarkQuery query,
    MediaBookmark bookmark,
  ) async {
    final actions = ref.read(mediaBookmarkActionsProvider);
    await _showBookmarkDialog(
      context,
      title: '编辑笔记',
      positionLabel: _duration(bookmark.position),
      initialNote: bookmark.note,
      onSave: (note) async {
        await actions.updateNote(
          query: query,
          bookmarkId: bookmark.id,
          note: note,
        );
      },
    );
  }

  Future<void> _deleteBookmark(
    BuildContext context,
    WidgetRef ref,
    MediaBookmarkQuery query,
    MediaBookmark bookmark,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (dialogContext) => PredictiveBackDialog(
        child: AlertDialog(
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

enum _BookmarkAction { edit, delete }

class _PlaybackBookmarkTile extends StatelessWidget {
  const _PlaybackBookmarkTile({
    super.key,
    required this.time,
    required this.note,
    required this.onPlay,
    required this.onEdit,
    required this.onDelete,
  });

  final String time;
  final String? note;
  final VoidCallback onPlay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = note?.trim() ?? '';
    return Material(
      type: MaterialType.transparency,
      borderRadius: AppShape.cardBorder,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: '从 $time 播放',
                        excludeSemantics: true,
                        child: Text(
                          time,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    PopupMenuButton<_BookmarkAction>(
                      tooltip: '$time 书签操作',
                      useRootNavigator: true,
                      clipBehavior: Clip.antiAlias,
                      borderRadius: BorderRadius.circular(AppShape.pill),
                      popUpAnimationStyle:
                          MediaQuery.disableAnimationsOf(context)
                          ? AnimationStyle.noAnimation
                          : null,
                      icon: const Icon(Icons.more_horiz_rounded),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _BookmarkAction.edit,
                          child: Text('编辑笔记'),
                        ),
                        PopupMenuItem(
                          value: _BookmarkAction.delete,
                          child: Text('删除书签'),
                        ),
                      ],
                      onSelected: (action) {
                        switch (action) {
                          case _BookmarkAction.edit:
                            onEdit();
                          case _BookmarkAction.delete:
                            onDelete();
                        }
                      },
                    ),
                  ],
                ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: Text(text, style: theme.textTheme.bodyLarge),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showBookmarkDialog(
  BuildContext context, {
  required String title,
  required String positionLabel,
  required Future<void> Function(String? note) onSave,
  String? initialNote,
}) => showDialog<void>(
  context: context,
  animationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => _BookmarkEditDialog(
    title: title,
    positionLabel: positionLabel,
    initialNote: initialNote,
    onSave: onSave,
  ),
);

class _BookmarkEditDialog extends StatefulWidget {
  const _BookmarkEditDialog({
    required this.title,
    required this.positionLabel,
    required this.onSave,
    this.initialNote,
  });

  final String title;
  final String positionLabel;
  final String? initialNote;
  final Future<void> Function(String? note) onSave;

  @override
  State<_BookmarkEditDialog> createState() => _BookmarkEditDialogState();
}

class _BookmarkEditDialogState extends State<_BookmarkEditDialog> {
  late final TextEditingController _noteController = TextEditingController(
    text: widget.initialNote,
  );

  final _noteFocus = FocusNode();
  bool _saving = false;
  bool _confirmingExit = false;
  String? _error;

  bool get _hasChanges =>
      _noteController.text.trim() != (widget.initialNote ?? '').trim();

  @override
  void initState() {
    super.initState();
    _noteController.addListener(_draftChanged);
  }

  void _draftChanged() => setState(() {});

  Future<void> _requestClose() async {
    if (_saving || _confirmingExit) return;
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }
    _confirmingExit = true;
    _noteFocus.unfocus();
    final discard = await showDiscardChangesDialog(
      context,
      title: '放弃未保存的笔记？',
      message: '退出后，本次修改不会保存。',
    );
    _confirmingExit = false;
    if (!mounted) return;
    if (discard == true) {
      Navigator.pop(context);
    } else {
      _noteFocus.requestFocus();
    }
  }

  Future<void> _save() async {
    if (_saving || _confirmingExit) return;
    final note = _noteController.text.trim();
    _noteFocus.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(note.isEmpty ? null : note);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = parseApiErrorInfo(error).code == 'media_bookmark_exists'
            ? '这个时间点已有书签，请返回编辑现有笔记。'
            : formatApiErrorMessage(error, fallbackMessage: '笔记保存失败，请重试');
      });
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BrowserLeaveGuard(
    enabled: _saving || _hasChanges,
    child: PopScope<void>(
      canPop: !_saving && !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: AdaptiveFormDialog(
        title: widget.title,
        contentBuilder: (context, width, short) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '时间点 ${widget.positionLabel}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _noteController,
              focusNode: _noteFocus,
              enabled: !_saving,
              autofocus: true,
              maxLength: 2000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '笔记（可选）',
                hintText: '为什么这个时间点值得回来？',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: AppSpacing.sm,
          overflowSpacing: AppSpacing.xs,
          children: [
            TextButton(
              onPressed: _saving ? null : _requestClose,
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    ),
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
        key: ValueKey(selectedType),
        padding: EdgeInsets.zero,
        shrinkWrap: segments.length <= 6,
        physics: segments.length <= 6
            ? const NeverScrollableScrollPhysics()
            : null,
        itemCount: segments.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final segment = segments[index];
          if (segment.segmentType == MediaSegmentType.transcript) {
            final activeColor = index == selectedIndex
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent;
            return ExpansionTile(
              key: ValueKey(
                'transcript-${segment.mediaAssetId}-${segment.startPosition.inMilliseconds}',
              ),
              backgroundColor: activeColor,
              collapsedBackgroundColor: activeColor,
              title: Text(
                '${_duration(segment.startPosition)} · ${segment.title}',
              ),
              subtitle: Text(
                segment.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(segment.fullText),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => actions.activate(
                      widget.request,
                      initialPosition: segment.startPosition,
                      startPlaying: true,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('从此处播放'),
                  ),
                ),
              ],
            );
          }
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
            subtitle:
                segment.excerpt.trim().isEmpty ||
                    segment.excerpt.trim() == segment.title.trim()
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
    final compact = WindowMetrics.of(context).heightClass.isCompact;
    final status = state.loading
        ? '正在载入'
        : state.failure != null
        ? mediaFailureLabel(state.failure!, audioOnly: request.audioOnly)
        : state.videoAudioOnly && !request.audioOnly
        ? '仅听声音'
        : null;

    return Material(
      key: const ValueKey('global-mini-player'),
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Semantics(
          hint: '展开当前播放',
          child: InkWell(
            onTap: () => context.push('/player'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 56 : 72),
              child: Row(
                children: [
                  SizedBox(
                    width: compact ? 72 : 88,
                    height: compact ? 56 : 72,
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
                            child: _PlaybackVideoView(controller: player),
                          ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (status != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
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
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: AppShape.cardBorder,
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              heightFactor: 1,
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: PictureInPictureTarget(
                  controller: controller,
                  child: _PlaybackVideoView(controller: controller),
                ),
              ),
            ),
          ),
        ),
        _PlaybackControls(controller: controller),
      ],
    ),
  );
}

/// The web decoder owns one HTML element. Mount it only after the previous
/// route has released its platform view, otherwise disposal removes the new
/// route's video element as well.
class _PlaybackVideoView extends ConsumerWidget {
  const _PlaybackVideoView({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = TickerMode.valuesOf(context).enabled;
    if (!kIsWeb) {
      return _PlaybackVideoMount(controller: controller, active: enabled);
    }
    final route = ModalRoute.of(context);
    final rootRoute = context
        .dependOnInheritedWidgetOfExactType<_PlaybackPage>()
        ?.route;
    final observer = ref.watch(playbackRouteObserverProvider);
    return ValueListenableBuilder(
      valueListenable: observer.topPage,
      builder: (context, _, _) => _PlaybackVideoMount(
        controller: controller,
        active:
            enabled && observer.ownsPage(route) && observer.ownsPage(rootRoute),
        prepareView: ref
            .read(globalPlaybackProvider.notifier)
            .preservePlaybackOnViewRemoval,
      ),
    );
  }
}

class _PlaybackVideoMount extends StatefulWidget {
  const _PlaybackVideoMount({
    required this.controller,
    required this.active,
    this.prepareView,
  });

  final VideoPlayerController controller;
  final bool active;
  final Future<void> Function(Future<Object?>)? prepareView;

  @override
  State<_PlaybackVideoMount> createState() => _PlaybackVideoMountState();
}

class _PlaybackVideoMountState extends State<_PlaybackVideoMount> {
  bool _visible = false;
  bool _mountScheduled = false;

  @override
  void initState() {
    super.initState();
    _updateVisibility();
  }

  @override
  void didUpdateWidget(covariant _PlaybackVideoMount oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateVisibility();
  }

  void _updateVisibility() {
    if (!widget.active) {
      _visible = false;
    } else if (!kIsWeb) {
      _visible = true;
    } else if (!_visible && !_mountScheduled) {
      _mountScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(Duration.zero);
        _mountScheduled = false;
        if (mounted && widget.active) {
          // The destination may load after the route animation has finished.
          // Keep the playback intent until this view has actually mounted.
          final mountedFrame = Completer<void>();
          unawaited(widget.prepareView?.call(mountedFrame.future));
          setState(() => _visible = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            mountedFrame.complete();
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? VideoPlayer(widget.controller) : const SizedBox.expand();
}

class _AudioControls extends StatelessWidget {
  const _AudioControls({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: AppShape.cardBorder,
    child: _PlaybackControls(controller: controller),
  );
}

class _PlaybackControls extends ConsumerStatefulWidget {
  const _PlaybackControls({required this.controller});

  final VideoPlayerController controller;

  @override
  ConsumerState<_PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<_PlaybackControls> {
  double? _scrubPosition;

  @override
  void didUpdateWidget(covariant _PlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _scrubPosition = null;
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: widget.controller,
    builder: (context, value, _) {
      final duration = value.duration.inMilliseconds.toDouble();
      final maximum = duration > 0 ? duration : 1.0;
      final position =
          (_scrubPosition ?? value.position.inMilliseconds.toDouble()).clamp(
            0.0,
            maximum,
          );
      final buffered = value.buffered
          .fold<double>(position, (end, range) {
            final next = range.end.inMilliseconds.toDouble();
            return next > end ? next : end;
          })
          .clamp(0.0, maximum);
      final actions = ref.read(globalPlaybackProvider.notifier);
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: value.isPlaying ? '暂停' : '播放',
              onPressed: actions.togglePlayback,
              icon: Icon(
                value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    label: '播放进度',
                    value: position,
                    max: maximum,
                    secondaryTrackValue: buffered,
                    semanticFormatterCallback: (milliseconds) =>
                        '${_duration(Duration(milliseconds: milliseconds.round()))} / ${_duration(value.duration)}',
                    onChanged: duration > 0
                        ? (milliseconds) =>
                              setState(() => _scrubPosition = milliseconds)
                        : null,
                    onChangeEnd: duration > 0
                        ? (milliseconds) async {
                            final player = widget.controller;
                            await actions.seekTo(
                              Duration(milliseconds: milliseconds.round()),
                            );
                            if (mounted &&
                                player == widget.controller &&
                                _scrubPosition == milliseconds) {
                              setState(() => _scrubPosition = null);
                            }
                          }
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: AppSpacing.sm,
                        children: [
                          Text(
                            _duration(Duration(milliseconds: position.round())),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            _duration(value.duration),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _PlayerFrame extends StatelessWidget {
  const _PlayerFrame({
    required this.audioOnly,
    required this.child,
    this.minHeight,
  });

  final bool audioOnly;
  final Widget child;
  final double? minHeight;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: AppShape.cardBorder,
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.constrainHeight(
              minHeight ?? (audioOnly ? 88 : 240),
            ),
          ),
          child: Center(child: child),
        ),
      ),
    ),
  );
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.label, required this.onRetry});

  final String label;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ],
      ),
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
