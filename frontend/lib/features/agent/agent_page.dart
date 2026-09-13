import '../../routing/app_navigation.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/markdown_reading.dart';
import '../../theme/design_tokens.dart';
import 'models/agent_result.dart';
import 'providers/agent_controller.dart';
import 'providers/agent_draft_store.dart';
import 'widgets/agent_citation_tile.dart';
import 'widgets/agent_confirmation_panel.dart';
import 'widgets/agent_tool_event.dart';

class AgentPage extends ConsumerStatefulWidget {
  const AgentPage({super.key, this.initialSessionId, this.initialPrompt});

  final String? initialSessionId;
  final String? initialPrompt;

  @override
  ConsumerState<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends ConsumerState<AgentPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final AgentDraftStore _draftStore;
  Timer? _draftDebounce;
  String? _draftSessionId;
  String? _pendingInitialPrompt;
  int _draftLoadRevision = 0;
  bool _applyingDraft = false;

  AgentController get _controller =>
      ref.read(agentControllerProvider(widget.initialSessionId).notifier);
  AgentViewState get _agentState =>
      ref.read(agentControllerProvider(widget.initialSessionId));
  List<AgentSessionSummary> get _sessions => _agentState.sessions;
  List<AgentTimelineItem> get _timeline => _agentState.timeline;
  Set<String> get _decidingConfirmationIds =>
      _agentState.decidingConfirmationIds;
  String? get _sessionId => _agentState.sessionId;
  bool get _loading => _agentState.loading;
  bool get _streaming => _agentState.streaming;
  String? get _error => _agentState.error;

  @override
  void initState() {
    super.initState();
    _draftStore = ref.read(agentDraftStoreProvider);
    final initialPrompt = widget.initialPrompt?.trim();
    _pendingInitialPrompt = initialPrompt == null || initialPrompt.isEmpty
        ? null
        : initialPrompt;
    _inputController.text = _pendingInitialPrompt ?? '';
    _inputController.addListener(_onDraftChanged);
  }

  @override
  void dispose() {
    _draftLoadRevision += 1;
    _draftDebounce?.cancel();
    _inputController.removeListener(_onDraftChanged);
    final sessionId = _draftSessionId;
    if (sessionId != null) {
      unawaited(_persistDraft(sessionId, _inputController.text));
    }
    _inputController.dispose();
    _inputFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    if (_applyingDraft || _draftSessionId == null) return;
    _draftDebounce?.cancel();
    final sessionId = _draftSessionId!;
    final value = _inputController.text;
    _draftDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_persistDraft(sessionId, value)),
    );
  }

  Future<void> _persistDraft(String sessionId, String value) async {
    try {
      if (value.isEmpty) {
        await _draftStore.remove(sessionId);
      } else {
        await _draftStore.write(sessionId, value);
      }
    } catch (_) {
      // Draft persistence is best-effort and must not block the Agent workflow.
    }
  }

  Future<void> _activateDraftSession(String? sessionId) async {
    if (sessionId == null || sessionId == _draftSessionId) return;
    _draftDebounce?.cancel();
    final previousSessionId = _draftSessionId;
    if (previousSessionId != null) {
      unawaited(_persistDraft(previousSessionId, _inputController.text));
    }

    _draftSessionId = sessionId;
    final revision = ++_draftLoadRevision;
    final initialPrompt = _pendingInitialPrompt;
    _pendingInitialPrompt = null;
    if (initialPrompt != null) {
      _setDraftText(initialPrompt);
      await _persistDraft(sessionId, initialPrompt);
      return;
    }

    final textBeforeLoad = _inputController.text;
    String? storedDraft;
    try {
      storedDraft = await _draftStore.read(sessionId);
    } catch (_) {
      return;
    }
    if (!mounted ||
        revision != _draftLoadRevision ||
        sessionId != _draftSessionId ||
        _inputController.text != textBeforeLoad) {
      return;
    }
    _setDraftText(storedDraft ?? '');
  }

  void _setDraftText(String value) {
    _applyingDraft = true;
    _inputController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _applyingDraft = false;
  }

  Future<void> _removeCurrentDraft() async {
    _draftDebounce?.cancel();
    final sessionId = _draftSessionId;
    if (sessionId != null) {
      await _persistDraft(sessionId, '');
    }
    _setDraftText('');
  }

  Future<void> _bootstrap() async {
    await _controller.bootstrap();
  }

  Future<void> _createSession() async {
    await _controller.createSession();
    _scrollToBottom();
  }

  Future<void> _selectSession(String sessionId) async {
    await _controller.selectSession(sessionId);
    _scrollToBottom();
  }

  Future<void> _sendPrompt() async {
    if (_streaming) return;
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    await _removeCurrentDraft();
    await _controller.sendPrompt(text);
    _scrollToBottom();
  }

  Future<void> _decideConfirmation(
    AgentConfirmation confirmation,
    bool approved,
  ) async {
    await _controller.decideConfirmation(confirmation, approved);
    _scrollToBottom();
  }

  Future<void> _redo() async {
    await _controller.redo();
    _scrollToBottom();
  }

  Future<void> _stop() async {
    await _controller.stop();
    _scrollToBottom();
  }

  Future<void> _clearSession() async {
    await _removeCurrentDraft();
    await _controller.clearSession();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: AppMotion.contentSwap,
        curve: AppMotion.standardCurve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = agentControllerProvider(widget.initialSessionId);
    ref.listen(
      provider.select((state) => state.timeline),
      (_, _) => _scrollToBottom(),
    );
    ref.listen(
      provider.select((state) => state.sessionId),
      (_, sessionId) => unawaited(_activateDraftSession(sessionId)),
    );
    ref.watch(provider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final metrics = WindowMetrics.fromSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final supportsSessionPane = metrics.supportsSupportingPane;
        final supportsEvidencePane =
            supportsSessionPane &&
            metrics.widthClass.atLeast(WindowWidthClass.large) &&
            _timeline.any(
              (item) =>
                  item.kind == AgentTimelineKind.toolCall ||
                  item.kind == AgentTimelineKind.toolResult,
            );
        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            leading: const AppBackButton(),
            toolbarHeight: metrics.heightClass.isCompact ? 48 : null,
            title: const Text('Agent 工作台'),
            actions: [
              if (!supportsSessionPane)
                IconButton(
                  tooltip: '选择 Agent 会话',
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  icon: const Icon(Icons.forum_outlined),
                ),
              PopupMenuButton<String>(
                tooltip: '会话操作',
                onSelected: (action) {
                  switch (action) {
                    case 'redo':
                      _redo();
                    case 'refresh':
                      _bootstrap();
                    case 'clear':
                      _clearSession();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'refresh',
                    enabled: !_streaming,
                    child: const Text('刷新会话'),
                  ),
                  PopupMenuItem(
                    value: 'redo',
                    enabled: !_streaming && _timeline.isNotEmpty,
                    child: const Text('重做上一步'),
                  ),
                  PopupMenuItem(
                    value: 'clear',
                    enabled: !_streaming && _timeline.isNotEmpty,
                    child: const Text('清空当前会话'),
                  ),
                ],
              ),
            ],
          ),
          endDrawer: supportsSessionPane
              ? null
              : Drawer(
                  width:
                      (AppPane.supportingWidth *
                              MediaQuery.textScalerOf(context).scale(16) /
                              16)
                          .clamp(0.0, constraints.maxWidth * 0.9),
                  child: SafeArea(
                    child: _SessionPane(state: this, closeAfterSelection: true),
                  ),
                ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : _sessionId == null && _error != null
              ? _AgentUnavailable(message: _error!, onRetry: _bootstrap)
              : supportsSessionPane
              ? Row(
                  children: [
                    SizedBox(
                      width: AppPane.supportingWidth,
                      child: _SessionPane(state: this),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _ConversationPane(
                        state: this,
                        showInlineCitations: !supportsEvidencePane,
                      ),
                    ),
                    if (supportsEvidencePane) ...[
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: AppPane.supportingWidth,
                        child: _EvidenceRunPane(timeline: _timeline),
                      ),
                    ],
                  ],
                )
              : _ConversationPane(state: this),
        );
      },
    );
  }
}

class _AgentUnavailable extends StatelessWidget {
  const _AgentUnavailable({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 44,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text('暂时无法打开 Agent 工作台', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.state,
    this.showInlineCitations = true,
  });

  final _AgentPageState state;
  final bool showInlineCitations;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: state._timeline.isEmpty
              ? const SizedBox.expand()
              : ListView.builder(
                  controller: state._scrollController,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: state._timeline.length,
                  itemBuilder: (context, index) => Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppPane.readableMaxWidth,
                      ),
                      child: _TimelineTile(
                        item: state._timeline[index],
                        showInlineCitations: showInlineCitations,
                        onDecide: state._decideConfirmation,
                        confirmationPending: state._decidingConfirmationIds
                            .contains(state._timeline[index].confirmation?.id),
                      ),
                    ),
                  ),
                ),
        ),
        if (state._error != null)
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppPane.readableMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: _InlineError(message: state._error!),
              ),
            ),
          ),
        SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppPane.readableMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: AppShape.paneBorder,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: state._inputController,
                            focusNode: state._inputFocus,
                            minLines: 1,
                            maxLines: WindowMetrics.of(context).isShortLandscape
                                ? 2
                                : 5,
                            textInputAction: TextInputAction.newline,
                            decoration: const InputDecoration(
                              hintText: '输入问题或指令',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: state._inputController,
                          builder: (context, value, _) => IconButton.filled(
                            tooltip: state._streaming ? '停止' : '发送',
                            onPressed: state._streaming
                                ? state._stop
                                : value.text.trim().isEmpty
                                ? null
                                : state._sendPrompt,
                            icon: Icon(
                              state._streaming
                                  ? Icons.stop_rounded
                                  : Icons.arrow_upward_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _SessionPane extends StatelessWidget {
  const _SessionPane({required this.state, this.closeAfterSelection = false});

  final _AgentPageState state;
  final bool closeAfterSelection;

  Future<void> _createSession(BuildContext context) async {
    await state._createSession();
    if (closeAfterSelection && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _selectSession(BuildContext context, String sessionId) async {
    await state._selectSession(sessionId);
    if (closeAfterSelection && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Material(
      color: closeAfterSelection
          ? theme.drawerTheme.backgroundColor ??
                theme.colorScheme.surfaceContainerLow
          : theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Expanded(child: Text('会话', style: theme.textTheme.titleMedium)),
            IconButton.filledTonal(
              tooltip: '新建会话',
              onPressed: state._streaming
                  ? null
                  : () => _createSession(context),
              icon: const Icon(Icons.add_rounded),
            ),
            if (closeAfterSelection)
              IconButton(
                tooltip: '关闭会话列表',
                onPressed: () =>
                    state._scaffoldKey.currentState?.closeEndDrawer(),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => CustomScrollView(
        slivers: [
          if (constraints.maxHeight >= 240)
            PinnedHeaderSliver(child: header)
          else
            SliverToBoxAdapter(child: header),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              0,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            sliver: SliverList.builder(
              itemCount: state._sessions.length,
              itemBuilder: (context, index) {
                final session = state._sessions[index];
                return _SessionTile(
                  session: session,
                  selected: session.id == state._sessionId,
                  onTap: state._streaming
                      ? null
                      : () => _selectSession(context, session.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final AgentSessionSummary session;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: AppShape.cardBorder,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          selected: selected,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Text(
            session.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: session.pendingConfirmations > 0
              ? Text('${session.pendingConfirmations} 个待确认')
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.item,
    required this.showInlineCitations,
    required this.onDecide,
    required this.confirmationPending,
  });

  final AgentTimelineItem item;
  final bool showInlineCitations;
  final Future<void> Function(AgentConfirmation confirmation, bool approved)
  onDecide;
  final bool confirmationPending;

  @override
  Widget build(BuildContext context) {
    return switch (item.kind) {
      AgentTimelineKind.user => _Bubble(
        alignRight: true,
        child: SelectableText(item.text),
      ),
      AgentTimelineKind.assistant ||
      AgentTimelineKind.assistantDraft => _Bubble(
        child: item.kind == AgentTimelineKind.assistantDraft
            ? const LinearProgressIndicator(minHeight: 3)
            : MarkdownBody(
                data: item.text,
                selectable: true,
                styleSheet: readingMarkdownStyle(context),
                builders: {'code': CodeElementBuilder(context)},
                onTapLink: (_, href, _) {
                  final uri = Uri.tryParse(href ?? '');
                  if (uri != null &&
                      !uri.hasScheme &&
                      !uri.hasAuthority &&
                      RegExp(
                        r'^/(collection|events)/\d+$',
                      ).hasMatch(uri.path)) {
                    openAppLocation(context, uri.toString());
                  } else {
                    SafeUrlLauncher.openExternal(context, href);
                  }
                },
                // Model output does not own media assets. Keep media in the
                // cited content page instead of fetching arbitrary image URLs.
                // ignore: deprecated_member_use
                imageBuilder: (_, _, alt) => Text(alt ?? '图片'),
              ),
      ),
      AgentTimelineKind.toolCall => AgentToolEvent(
        event: item.event!,
        running: true,
        showCitations: showInlineCitations,
      ),
      AgentTimelineKind.toolResult => AgentToolEvent(
        event: item.event!,
        running: false,
        showCitations: showInlineCitations,
      ),
      AgentTimelineKind.confirmation => AgentConfirmationPanel(
        confirmation: item.confirmation!,
        onDecide: onDecide,
        pending: confirmationPending,
      ),
      AgentTimelineKind.notice => _Notice(
        text: item.text,
        details: item.details,
      ),
      AgentTimelineKind.error => _InlineError(message: item.text),
    };
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.child, this.alignRight = false});

  final Widget child;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: AppPane.readableMaxWidth),
        margin: const EdgeInsets.only(bottom: AppSpacing.lg),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: alignRight
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: AppShape.cardBorder,
              )
            : null,
        child: child,
      ),
    );
  }
}

class _EvidenceRunPane extends StatelessWidget {
  const _EvidenceRunPane({required this.timeline});

  final List<AgentTimelineItem> timeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toolItems = timeline
        .where(
          (item) =>
              item.kind == AgentTimelineKind.toolCall ||
              item.kind == AgentTimelineKind.toolResult,
        )
        .toList(growable: false);
    final citations = <AgentCitation>[];
    final citationKeys = <String>{};
    for (final item in toolItems) {
      for (final citation in citationsFromToolResult(item.event!)) {
        final key = '${citation.kind}:${citation.appRoute}:${citation.title}';
        if (citationKeys.add(key)) citations.add(citation);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('证据与运行', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${citations.length} 条引用 · ${toolItems.length} 次工具调用',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (citations.isNotEmpty) ...[
                Text('引用', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                for (final citation in citations)
                  AgentCitationTile(citation: citation, showExcerpt: true),
                const SizedBox(height: 16),
              ],
              Text('工具过程', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              for (final item in toolItems)
                _RunListTile(
                  event: item.event!,
                  running: item.kind == AgentTimelineKind.toolCall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RunListTile extends StatelessWidget {
  const _RunListTile({required this.event, required this.running});

  final Map<String, dynamic> event;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final failed = !running && (event['ok'] == false || event['error'] != null);
    final theme = Theme.of(context);
    final summary = actionSummaryFromToolResult(event);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        running
            ? Icons.pending_outlined
            : failed
            ? Icons.error_outline_rounded
            : Icons.check_circle_outline_rounded,
        color: failed ? theme.colorScheme.error : null,
      ),
      title: Text(event['tool']?.toString() ?? 'tool'),
      subtitle: Text(
        summary ??
            (running
                ? '调用中'
                : failed
                ? '执行失败'
                : '执行完成'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.details});

  final String text;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (details != null) {
      return ExpansionTile(
        title: Text(text),
        tilePadding: EdgeInsets.zero,
        children: [SelectableText(details!)],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: AppShape.cardBorder,
      ),
      child: SelectableText(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
