import '../../core/widgets/app_filter_menu.dart';
import '../../core/layout/app_page_body.dart';
import '../../layout/root_page_actions.dart';
import '../collection/content_detail_page.dart';
import '../collection/models/content.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/layout/app_list_detail_workspace.dart';
import '../../core/network/sse_service.dart';
import '../../core/network/api_client.dart';
import '../../theme/design_tokens.dart';
import 'models/distribution_rule.dart';
import 'models/queue_item.dart';
import 'providers/distribution_rules_provider.dart';
import 'providers/bot_chats_provider.dart';
import 'providers/queue_provider.dart';
import '../dashboard/providers/dashboard_provider.dart' as dashboard;
import '../settings/providers/settings_provider.dart';
import '../settings/utils/setting_value.dart';
import 'widgets/queue_content_list.dart';
import 'widgets/rule_list_tile.dart';
import '../settings/presentation/tabs/push_tab.dart';
import '../settings/presentation/widgets/setting_components.dart';
import '../../core/utils/toast.dart';

class DistributionPage extends ConsumerStatefulWidget {
  const DistributionPage({
    super.key,
    this.initialTab,
    this.editorRouteKey,
    this.ruleId,
    this.filterRuleId,
    this.selectedContentId,
    this.creatingRule = false,
    this.configuration,
  });

  static void showTargets(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: Column(
              children: [
                ListTile(
                  title: const Text('推送目标'),
                  trailing: IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Expanded(child: PushTab(targetsOnly: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final String? initialTab;
  final ValueKey<String>? editorRouteKey;
  final int? ruleId;
  final int? filterRuleId;
  final int? selectedContentId;
  final bool creatingRule;
  final Widget? configuration;

  @override
  ConsumerState<DistributionPage> createState() => _DistributionPageState();
}

enum _DistributionDomainView { queue, history, rules, targets }

class _DistributionDomainTabs extends StatefulWidget {
  const _DistributionDomainTabs({required this.view, required this.onChanged});

  final _DistributionDomainView view;
  final ValueChanged<_DistributionDomainView> onChanged;

  @override
  State<_DistributionDomainTabs> createState() =>
      _DistributionDomainTabsState();
}

class _DistributionDomainTabsState extends State<_DistributionDomainTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: 4,
    initialIndex: widget.view.index,
    vsync: this,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The parent queue page stays mounted beneath history. Restore its own
    // selection when it becomes current again after browser or system back.
    if (ModalRoute.isCurrentOf(context) ?? true) {
      _controller.index = widget.view.index;
    }
  }

  @override
  void didUpdateWidget(covariant _DistributionDomainTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) _controller.index = widget.view.index;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TabBar.secondary(
    controller: _controller,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    dividerColor: Colors.transparent,
    tabs: const [
      Tab(text: '待发送'),
      Tab(text: '发送记录'),
      Tab(text: '规则'),
      Tab(text: '目标'),
    ],
    onTap: (index) => widget.onChanged(_DistributionDomainView.values[index]),
  );
}

class _DistributionPageState extends ConsumerState<DistributionPage> {
  _DistributionDomainView _distributionView = _DistributionDomainView.queue;
  int? _selectedRuleId;
  StreamSubscription<SseEvent>? _sseSub;
  ShareCard? _preview;
  LocalHistoryEntry? _readerHistory;

  @override
  void initState() {
    super.initState();
    _distributionView = _distributionViewFromTab(widget.initialTab);
    _selectedRuleId = widget.filterRuleId;
    _bindRealtimeEvents();
    _scheduleQueueFilter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncReaderHistory();
    });
  }

  @override
  void didUpdateWidget(DistributionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterRuleId != widget.filterRuleId) {
      _selectedRuleId = widget.filterRuleId;
    }
    _scheduleQueueFilter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncReaderHistory();
    });
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() {
        _distributionView = _distributionViewFromTab(widget.initialTab);
      });
    }
  }

  void _showView(_DistributionDomainView view) {
    final path = switch (view) {
      _DistributionDomainView.queue => '/automation/distribution',
      _DistributionDomainView.history => '/automation/distribution/history',
      _DistributionDomainView.rules => '/automation/distribution/rules',
      _DistributionDomainView.targets => '/automation/distribution/targets',
    };
    final isQueue =
        view == _DistributionDomainView.queue ||
        view == _DistributionDomainView.history;
    context.go(
      Uri(
        path: path,
        queryParameters: isQueue && _selectedRuleId != null
            ? {'rule': '$_selectedRuleId'}
            : null,
      ).toString(),
    );
  }

  void _scheduleQueueFilter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncQueueFilter();
    });
  }

  QueueStatus get _queueStatus =>
      _distributionView == _DistributionDomainView.history
      ? QueueStatus.pushed
      : QueueStatus.willPush;

  void _syncQueueFilter() {
    if (_distributionView != _DistributionDomainView.queue &&
        _distributionView != _DistributionDomainView.history) {
      return;
    }
    ref
        .read(queueFilterProvider.notifier)
        .setFilter(ruleId: _selectedRuleId, status: _queueStatus);
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  void _bindRealtimeEvents() {
    ref.read(sseServiceProvider.notifier);
    _sseSub?.cancel();
    _sseSub = SseEventBus().eventStream.listen((event) {
      if (!mounted) return;

      switch (event.type) {
        case 'queue_updated':
          ref.invalidate(dashboard.queueStatsProvider);
          break;
        case 'content_pushed':
        case 'distribution_push_success':
          ref.invalidate(botChatsProvider);
          break;
        case 'distribution_push_failed':
          break;
      }
    });
  }

  void _syncReaderHistory() {
    if (widget.selectedContentId == null) {
      final entry = _readerHistory;
      _readerHistory = null;
      entry?.remove();
    } else if (_readerHistory == null) {
      late final LocalHistoryEntry entry;
      entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (_readerHistory != entry) return;
          _readerHistory = null;
          _closeReader();
        },
      );
      _readerHistory = entry;
      ModalRoute.of(context)!.addLocalHistoryEntry(entry);
    }
  }

  void _openContent(QueueItem item) {
    _preview = ShareCard(
      id: item.contentId,
      platform: item.platform,
      url: '',
      title: item.title,
      mediaAssets: item.mediaAssets,
    );
    if (!AppListDetailWorkspace.supportsSplit(context)) {
      context.push('/collection/${item.contentId}', extra: _preview);
      return;
    }
    final uri = GoRouterState.of(context).uri;
    final location = uri
        .replace(
          queryParameters: {
            ...uri.queryParametersAll,
            'item': ['${item.contentId}'],
          },
        )
        .toString();
    widget.selectedContentId == null
        ? context.go(location)
        : context.replace(location);
  }

  void _closeReader() {
    final uri = GoRouterState.of(context).uri;
    final query = {...uri.queryParametersAll}..remove('item');
    context.replace(uri.replace(queryParameters: query).toString());
  }

  @override
  Widget build(BuildContext context) {
    final editorKey = widget.editorRouteKey;
    final configuration = widget.configuration;
    final creating = widget.ruleId == null;
    final contentId = widget.selectedContentId;
    final preview = _preview?.id == contentId ? _preview : null;
    return AppListDetailWorkspace(
      onClose: editorKey != null
          ? () => context.go('/automation/distribution/rules')
          : _closeReader,
      selectedId:
          editorKey ?? (contentId == null ? null : ('content', contentId)),
      list: Scaffold(
        appBar: AppBar(
          toolbarHeight: WindowMetrics.of(context).toolbarHeight,
          title: const Text('推送'),
          leading: buildRootPageLeading(context),
        ),
        body: _buildDistributionDomain(),
      ),
      detailBuilder: (deferBody, focused, toggleFocus) => editorKey != null
          ? Scaffold(
              appBar: AppBar(
                leading: BackButton(
                  onPressed: () => context.go('/automation/distribution/rules'),
                ),
                title: Text(creating ? '新建规则' : '编辑规则'),
              ),
              body: Semantics(container: true, child: configuration),
            )
          : ContentDetailPage(
              contentId: contentId!,
              preview: preview,
              deferBody: deferBody,
              focused: focused,
              onToggleFocus: toggleFocus,
              onClose: _closeReader,
            ),
    );
  }

  _DistributionDomainView _distributionViewFromTab(String? tab) =>
      switch (tab) {
        'history' => _DistributionDomainView.history,
        'rules' => _DistributionDomainView.rules,
        'targets' => _DistributionDomainView.targets,
        _ => _DistributionDomainView.queue,
      };

  Widget _buildDistributionDomain() => _buildDistributionContent();

  Color get _rulesBackgroundColor =>
      Theme.of(context).colorScheme.surfaceContainerLow;

  Widget _buildRules({bool showAutomaticSending = false}) => AppPageBody(
    child: LayoutBuilder(
      builder: (context, constraints) {
        const inset = 16.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(inset, 12, inset, 24),
          children: [
            if (showAutomaticSending) _buildAutomaticSending(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _openCreateRule,
                  icon: const Icon(Icons.add),
                  label: const Text('新建规则'),
                ),
              ),
            ),
            ref
                .watch(distributionRulesProvider)
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => TextButton(
                    onPressed: () => ref.invalidate(distributionRulesProvider),
                    child: const Text('规则加载失败，重试'),
                  ),
                  data: (rules) => Column(
                    children: [
                      for (final rule in rules)
                        Padding(
                          key: ValueKey(rule.id),
                          padding: const EdgeInsets.only(bottom: 4),
                          child: RuleListTile(
                            backgroundColor: _rulesBackgroundColor,
                            rule: rule,
                            isSelected: rule.id == widget.ruleId,
                            onTap: () => _openRule(rule),
                            onDelete: () => _confirmDeleteRule(rule),
                            onToggleEnabled: (value) =>
                                _toggleRuleEnabled(rule, value),
                          ),
                        ),
                    ],
                  ),
                ),
          ],
        );
      },
    ),
  );

  Widget _buildDistributionContent() {
    final header = <Widget>[
      _DistributionDomainTabs(view: _distributionView, onChanged: _showView),
      if ((_distributionView == _DistributionDomainView.queue ||
          _distributionView == _DistributionDomainView.history))
        _buildRuleSelector(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header.first,
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: _distributionView != _DistributionDomainView.rules,
                child: _buildRules(showAutomaticSending: true),
              ),
              if (_distributionView == _DistributionDomainView.targets)
                const PushTab(targetsOnly: true),
              if (_distributionView == _DistributionDomainView.queue ||
                  _distributionView == _DistributionDomainView.history)
                AppPageBody(child: _buildQueueList(header.skip(1).toList())),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAutomaticSending() => ref
      .watch(systemSettingsProvider)
      .when(
        data: (settings) => SettingSwitch(
          title: const Text('自动分发'),
          value:
              getSettingValue(settings, 'distribution_mode', 'auto') !=
              'paused',
          onChanged: (enabled) => ref
              .read(systemSettingsProvider.notifier)
              .updateSetting(
                'distribution_mode',
                enabled ? 'auto' : 'paused',
                category: 'automation',
              ),
        ),
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => TextButton(
          onPressed: () => ref.invalidate(systemSettingsProvider),
          child: const Text('自动分发设置加载失败，重试'),
        ),
      );

  Widget _buildDistributionState(List<Widget> header, Widget state) =>
      CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final section in header) SliverToBoxAdapter(child: section),
          SliverFillRemaining(hasScrollBody: false, child: state),
        ],
      );

  Widget _buildRuleSelector() {
    return ref
        .watch(distributionRulesProvider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              formatApiErrorMessage(error, fallbackMessage: '规则加载失败'),
            ),
          ),
          data: (rules) {
            final selected = rules
                .where((rule) => rule.id == _selectedRuleId)
                .firstOrNull;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: AppFilterMenu(
                    label: '规则',
                    value: selected?.id.toString() ?? 'all',
                    options: {
                      'all': '全部规则',
                      for (final rule in rules) '${rule.id}': rule.name,
                    },
                    onSelected: (value) {
                      final ruleId = value == 'all' ? null : int.parse(value);
                      final path =
                          _distributionView == _DistributionDomainView.history
                          ? '/automation/distribution/history'
                          : '/automation/distribution';
                      context.go(
                        Uri(
                          path: path,
                          queryParameters: ruleId == null
                              ? null
                              : {'rule': '$ruleId'},
                        ).toString(),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
  }

  Widget _buildQueueList(List<Widget> header) {
    if (widget.creatingRule) return const SizedBox.expand();
    final queueAsync = ref.watch(contentQueueProvider);
    final filter = ref.watch(queueFilterProvider);

    if (filter.ruleId != _selectedRuleId || filter.status != _queueStatus) {
      return _buildDistributionState(
        header,
        const Center(child: CircularProgressIndicator()),
      );
    }
    return queueAsync.when(
      loading: () => _buildDistributionState(
        header,
        const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => _buildDistributionState(
        header,
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(formatApiErrorMessage(e, fallbackMessage: '加载失败，请重试')),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.invalidate(contentQueueProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (response) {
        return QueueContentList(
          key: ValueKey((filter.ruleId, filter.status)),
          header: header,
          items: response.items,
          activeContentId: widget.selectedContentId,
          onOpen: _openContent,
          currentStatus: filter.status,
          onLoadMore: response.hasMore
              ? ref.read(contentQueueProvider.notifier).loadMore
              : null,
          onRefresh: () {
            ref.invalidate(contentQueueProvider);
          },
        );
      },
    );
  }

  void _navigateRule(String path) => context.go(path);

  void _openCreateRule() {
    _navigateRule('/automation/distribution/rules/new');
  }

  void _openRule(DistributionRule rule) {
    _navigateRule('/automation/distribution/rules/${rule.id}');
  }

  void _confirmDeleteRule(DistributionRule rule) {
    showDialog(
      context: context,
      animationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('删除规则“${rule.name}”及其待发送项？已发送记录仍保留。'),
        shape: RoundedRectangleBorder(borderRadius: AppShape.sheetBorder),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(distributionRulesProvider.notifier)
                    .deleteRule(rule.id);
                if (widget.ruleId == rule.id && mounted) {
                  context.go('/automation/distribution/rules');
                }
                if (_selectedRuleId == rule.id) {
                  setState(() => _selectedRuleId = null);
                  ref.read(queueFilterProvider.notifier).setRuleId(null);
                }
                if (mounted) {
                  ref.invalidate(contentQueueProvider);
                  Toast.show(context, '规则已删除');
                }
              } catch (e) {
                if (mounted) {
                  Toast.show(
                    context,
                    formatApiErrorMessage(e, fallbackMessage: '删除失败，请重试'),
                    isError: true,
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleRuleEnabled(DistributionRule rule, bool enabled) async {
    try {
      await ref
          .read(distributionRulesProvider.notifier)
          .toggleEnabled(rule.id, enabled);
    } catch (e) {
      if (mounted) {
        Toast.show(
          context,
          formatApiErrorMessage(e, fallbackMessage: '操作失败，请重试'),
          isError: true,
        );
      }
    }
  }
}
