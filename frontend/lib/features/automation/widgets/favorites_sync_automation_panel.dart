import '../../../core/constants/platform_constants.dart';
import '../../../core/widgets/app_setting_group.dart';
import '../../../core/layout/app_page_body.dart';
import '../../../core/layout/responsive_layout.dart';

import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/metadata_wrap.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../settings/utils/setting_value.dart';
import '../../accounts/telegram_account_page.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/adaptive_form_dialog.dart';
import '../../../core/widgets/app_filter_menu.dart';
import '../../../theme/design_tokens.dart';
import '../../settings/providers/favorites_sync_provider.dart';
import '../../settings/providers/settings_provider.dart';

class FavoritesSyncAutomationPanel extends ConsumerWidget {
  const FavoritesSyncAutomationPanel({
    super.key,
    this.initialPlatform,
    this.showBackButton = true,
    this.showPlatformLinks = true,
  });

  final String? initialPlatform;
  final bool showBackButton;
  final bool showPlatformLinks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = initialPlatform;
    Widget layout(String? heading, List<Widget> children) => Scaffold(
      appBar: heading == null
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: WindowMetrics.of(context).toolbarHeight,
              leading: showBackButton
                  ? BackButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/sources/sync');
                        }
                      },
                    )
                  : null,
              title: Text(heading),
            ),
      body: AppPageBody(
        maxWidth: AppPane.readableMaxWidth,
        child: ListView(
          key: PageStorageKey(platform ?? 'sync-overview'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: children,
        ),
      ),
    );
    if (platform == 'telegram') {
      return ref
          .watch(telegramAccountProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => layout('Telegram', [
              TextButton(
                onPressed: () => ref.invalidate(telegramAccountProvider),
                child: const Text('读取失败，重试'),
              ),
            ]),
            data: (account) => RefreshIndicator(
              onRefresh: () async {
                final _ = await ref.refresh(telegramAccountProvider.future);
              },
              child: layout('Telegram', [
                TelegramSyncControls(account: account),
                const SizedBox(height: 20),
                _RecentRunsList(runs: account.recentRuns, platform: 'telegram'),
              ]),
            ),
          );
    }
    final provider = favoritesSyncStatusProvider(platform);
    return ref
        .watch(provider)
        .when(
          data: (status) {
            final selected = status.platforms
                .where((p) => p.platform == platform)
                .firstOrNull;
            return RefreshIndicator(
              onRefresh: () async {
                final _ = await ref.refresh(provider.future);
              },
              child: layout(
                platform == null
                    ? (showPlatformLinks ? null : '全部平台')
                    : PlatformConstants.getName(platform),
                [
                  if (platform == null) ...[
                    if (showPlatformLinks)
                      _PlatformStatusGrid(platforms: status.platforms),
                    if (status.enabledPlatforms.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const _SyncCommandBar(enabled: true),
                    ],
                    const SizedBox(height: 12),
                    ExpansionTile(
                      leading: const Icon(Icons.tune_rounded),
                      title: const Text('同步设置'),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      children: [_SyncPolicyCard(status: status)],
                    ),
                  ] else if (selected != null) ...[
                    _PlatformSyncControls(
                      status: selected,
                      enabledPlatforms: status.enabledPlatforms,
                    ),
                    const SizedBox(height: 12),
                    _PolicyControlRow(
                      label: '读取频率',
                      value: selected.ratePerMinute.round(),
                      values: const [1, 3, 5, 10, 20],
                      suffix: '条/分钟',
                      onChanged: (v) => _updateFavoritesSyncSetting(
                        context,
                        ref,
                        key: 'favorites_sync_rate_${selected.platform}',
                        value: v,
                      ),
                    ),
                  ] else
                    const Text('未找到这个平台'),
                  const SizedBox(height: 20),
                  _RecentRunsList(
                    runs: status.recentRuns,
                    platform: selected?.platform,
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 44,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    formatApiErrorMessage(error, fallbackMessage: '收藏同步状态加载失败'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.invalidate(favoritesSyncStatusProvider),
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

class _SyncPolicyCard extends ConsumerWidget {
  const _SyncPolicyCard({required this.status});

  final FavoritesSyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(systemSettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        settings.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => const Text('策略读取失败，请刷新后重试'),
          data: (values) => AppSettingGroup(
            children: [
              SwitchListTile(
                shape: const RoundedRectangleBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                title: const Text('自动同步'),
                value: parseBoolSetting(
                  getSettingValue(
                    values,
                    'enable_favorites_sync_scheduler',
                    true,
                  ),
                  true,
                ),
                onChanged: (value) => _updateFavoritesSyncSetting(
                  context,
                  ref,
                  key: 'enable_favorites_sync_scheduler',
                  value: value,
                ),
              ),
              SwitchListTile(
                shape: const RoundedRectangleBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                title: const Text('允许手动同步未启用的平台'),
                value: parseBoolSetting(
                  getSettingValue(
                    values,
                    'allow_manual_favorites_sync_disabled_platform',
                    false,
                  ),
                  false,
                ),
                onChanged: (value) => _updateFavoritesSyncSetting(
                  context,
                  ref,
                  key: 'allow_manual_favorites_sync_disabled_platform',
                  value: value,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns =
                constraints.maxWidth >=
                    560 * MediaQuery.textScalerOf(context).scale(1)
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            final fields = <Widget>[
              _PolicyControlRow(
                label: '同步间隔',
                value: status.intervalMinutes,
                values: const [60, 180, 360, 720, 1440],
                suffix: '分钟',
                onChanged: (value) => _updateFavoritesSyncSetting(
                  context,
                  ref,
                  key: 'favorites_sync_interval_minutes',
                  value: value,
                ),
              ),
              _PolicyControlRow(
                label: '单轮上限',
                value: status.maxItems,
                values: const [20, 50, 100, 200],
                suffix: '条',
                onChanged: (value) => _updateFavoritesSyncSetting(
                  context,
                  ref,
                  key: 'favorites_sync_max_items',
                  value: value,
                ),
              ),
              AppFilterMenu(
                label: '重复内容',
                value: status.duplicateStrategy,
                options: const {'merge': '合并来源', 'skip': '跳过'},
                onSelected: (value) => _updateFavoritesSyncSetting(
                  context,
                  ref,
                  key: 'favorites_sync_duplicate_strategy',
                  value: value,
                ),
              ),
            ];
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final field in fields)
                    SizedBox(width: width, child: field),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _PolicyControlRow extends StatelessWidget {
  const _PolicyControlRow({
    required this.label,
    required this.value,
    required this.values,
    required this.suffix,
    required this.onChanged,
  });
  final String label;
  final int value;
  final List<int> values;
  final String suffix;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => AppFilterMenu(
    label: label,
    value: '$value',
    options: {
      for (final option in ({value, ...values}.toList()..sort()))
        '$option': '$option $suffix',
    },
    onSelected: (next) => onChanged(int.parse(next)),
  );
}

class _SyncCommandBar extends ConsumerStatefulWidget {
  const _SyncCommandBar({
    super.key,
    required this.enabled,
    this.platform,
    this.canSync = true,
  });

  final bool enabled;
  final String? platform;
  final bool canSync;

  @override
  ConsumerState<_SyncCommandBar> createState() => _SyncCommandBarState();
}

class _SyncCommandBarState extends ConsumerState<_SyncCommandBar> {
  String? _progress;

  Future<void> _run({required bool previewOnly}) async {
    if (_progress != null) return;
    final router = GoRouter.of(context);
    final sourceUri = router.routeInformationProvider.value.uri;
    setState(() => _progress = previewOnly ? '正在读取收藏…' : '正在提交同步…');
    try {
      final actions = ref.read(favoritesSyncActionsProvider);
      if (previewOnly) {
        final preview = await actions.previewSync(platform: widget.platform);
        if (mounted && router.routeInformationProvider.value.uri == sourceUri) {
          await _showPreviewDialog(context, preview);
        }
        return;
      }
      final runId = await actions.triggerSync(platform: widget.platform);
      if (!mounted || router.routeInformationProvider.value.uri != sourceUri) {
        return;
      }
      if (runId != null) {
        context.push('/tasks/$runId');
      } else {
        Toast.show(context, '同步任务已受理');
      }
    } catch (error) {
      if (mounted && router.routeInformationProvider.value.uri == sourceUri) {
        Toast.show(
          context,
          formatApiErrorMessage(error, fallbackMessage: '收藏同步请求失败'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && _progress == null;
    return Wrap(
      spacing: 8,
      children: [
        if (widget.canSync)
          FilledButton.icon(
            onPressed: enabled ? () => _run(previewOnly: false) : null,
            icon: const Icon(Icons.sync_rounded),
            label: Text(widget.platform == null ? '同步全部' : '同步收藏'),
          ),
        TextButton(
          onPressed: enabled ? () => _run(previewOnly: true) : null,
          child: const Text('预览收藏'),
        ),
        if (_progress != null) Text(_progress!),
      ],
    );
  }
}

class FavoritesSyncPlatformList extends ConsumerWidget {
  const FavoritesSyncPlatformList({
    super.key,
    required this.selectedPlatform,
    required this.onSelected,
  });
  final String selectedPlatform;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(favoritesSyncStatusProvider(null))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(favoritesSyncStatusProvider(null)),
            child: const Text('重新加载'),
          ),
        ),
        data: (status) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _PlatformStatusGrid(
              platforms: status.platforms,
              selectedPlatform: selectedPlatform,
              onSelected: onSelected,
            ),
          ],
        ),
      );
}

class _PlatformStatusGrid extends StatelessWidget {
  const _PlatformStatusGrid({
    required this.platforms,
    this.selectedPlatform,
    this.onSelected,
  });
  final String? selectedPlatform;
  final ValueChanged<String>? onSelected;

  final List<FavoritesPlatformStatus> platforms;

  @override
  Widget build(BuildContext context) {
    return AppSettingGroup(
      children: [
        if (onSelected != null)
          ListTile(
            shape: onSelected == null
                ? null
                : const RoundedRectangleBorder(
                    borderRadius: AppShape.cardMediaBorder,
                  ),
            title: const Text('全部平台'),
            selected: selectedPlatform == 'all',
            onTap: () => onSelected!('all'),
          ),
        for (final platform in platforms)
          ListTile(
            shape: onSelected == null
                ? null
                : const RoundedRectangleBorder(
                    borderRadius: AppShape.cardMediaBorder,
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            selected: selectedPlatform == platform.platform,
            title: Text(PlatformConstants.getName(platform.platform)),
            subtitle: Text(_platformStateLabel(platform)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onSelected != null
                ? onSelected!(platform.platform)
                : context.push('/sources/sync?platform=${platform.platform}'),
          ),
        ListTile(
          shape: onSelected == null
              ? null
              : const RoundedRectangleBorder(
                  borderRadius: AppShape.cardMediaBorder,
                ),
          selected: selectedPlatform == 'telegram',
          title: const Text('Telegram'),
          subtitle: const Text('已保存的消息与频道'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => onSelected != null
              ? onSelected!('telegram')
              : context.push('/sources/sync?platform=telegram'),
        ),
      ],
    );
  }
}

class _PlatformSyncControls extends ConsumerWidget {
  const _PlatformSyncControls({
    required this.status,
    required this.enabledPlatforms,
  });
  final List<String> enabledPlatforms;

  final FavoritesPlatformStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(systemSettingsProvider);
    final enabled = enabledPlatforms;
    final canSync =
        status.enabled ||
        (settings.value != null &&
            parseBoolSetting(
              getSettingValue(
                settings.value!,
                'allow_manual_favorites_sync_disabled_platform',
                false,
              ),
              false,
            ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(
            borderRadius: AppShape.cardMediaBorder,
          ),
          title: const Text('参与自动同步'),
          value: status.enabled,
          onChanged: settings.hasValue && status.capabilities.supported
              ? (value) => _updateFavoritesSyncSetting(
                  context,
                  ref,
                  key: 'favorites_sync_platforms',
                  value: value
                      ? {...enabled, status.platform}.toList()
                      : enabled.where((p) => p != status.platform).toList(),
                )
              : null,
        ),
        if (!status.capabilities.supported) const Text('暂未接入收藏同步'),
        if (!status.available && status.capabilities.supported)
          Text(
            status.statusError?['error_hint']?.toString() ??
                status.error ??
                '账号状态检查失败',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        if (status.capabilities.supported && status.available) ...[
          _SyncCommandBar(
            key: ValueKey(status.platform),
            enabled: status.authenticated != false || !status.enabled,
            platform: status.platform,
            canSync: canSync,
          ),
          if (status.authenticated == false)
            TextButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('管理账号'),
              onPressed: () => context.push('/accounts/${status.platform}'),
            ),
        ],
      ],
    );
  }
}

class _RecentRunsList extends ConsumerWidget {
  const _RecentRunsList({required this.runs, this.platform});
  final String? platform;

  final List<Map<String, dynamic>> runs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (runs.isEmpty) {
      return const _EmptyPanel(message: '暂无同步记录');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近同步',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        AppSettingGroup(
          children: [
            for (final run in runs) _RunTile(run: run, platform: platform),
          ],
        ),
      ],
    );
  }
}

class _RunTile extends ConsumerWidget {
  const _RunTile({required this.run, this.platform});
  final String? platform;

  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = _mapString(run, 'scope');
    final result = run['result'] as Map?;
    final reported = result?['results'] as Map?;
    final Map? measured;
    if (scope == platform) {
      measured = result?['result'] as Map?;
    } else {
      measured = reported?[platform] as Map?;
    }
    final status =
        measured?['status'] as String? ??
        _mapString(run, 'status') ??
        'unknown';
    final runId = _mapString(run, 'run_id');
    final completed = status == 'success' || status == 'ok';
    final added = measured?['imported'] as int?;
    final label = platform != null
        ? (measured?['status'] == null && scope == 'all'
              ? '全平台任务${_runStatusLabel(status)}'
              : completed && added != null
              ? (added == 0 ? '没有新收藏' : '新增 $added 条收藏')
              : _runStatusLabel(status))
        : (scope == 'all' ? '全部平台' : PlatformConstants.getName(scope ?? ''));
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 12, end: 4),
      leading: Icon(
        completed
            ? Icons.check_circle_outline
            : (status == 'failed' ||
                  status == 'error' ||
                  status == 'partial_success')
            ? Icons.error_outline
            : Icons.schedule,
      ),
      title: Text(label),
      subtitle: MetadataWrap(
        items: [
          if (platform == null) _runStatusLabel(status),
          if (_mapString(run, 'started_at') != null)
            _formatTime(_mapString(run, 'started_at')),
        ],
      ),
      trailing: runId == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: runId == null ? null : () => context.push('/tasks/$runId'),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: AppShape.cardBorder,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(message),
    );
  }
}

Future<void> _showPreviewDialog(
  BuildContext context,
  FavoritesSyncPreview preview,
) async {
  final theme = Theme.of(context);
  final label = preview.platform == 'all'
      ? '全平台'
      : PlatformConstants.getName(preview.platform);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AdaptiveFormDialog(
      title: '$label收藏同步预览',
      contentBuilder: (context, width, short) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '预计新增 ${preview.estimatedNew} 条',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('已获取 ${preview.fetched}'),
              Text('已存在 ${preview.existing}'),
              Text('跳过 ${preview.skipped}'),
            ],
          ),
          const SizedBox(height: 20),
          for (final item in preview.platforms)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PreviewPlatformSection(item: item),
            ),
        ],
      ),
      actions: OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}

class _PreviewPlatformSection extends StatelessWidget {
  const _PreviewPlatformSection({required this.item});
  final FavoritesSyncPlatformPreview item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = Text(
      PlatformConstants.getName(item.platform),
      style: theme.textTheme.titleMedium,
    );
    if (item.status == 'failed') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 4),
            Text(
              item.errorHint ?? item.error ?? '预览失败',
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
            ),
          ],
        ),
      );
    }
    final summary = MetadataWrap(
      items: ['预计新增 ${item.estimatedNew}', '已存在 ${item.existing}'],
    );
    if (item.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 4), summary],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
        const SizedBox(height: 4),
        summary,
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${item.items.take(5).length} 条候选样本',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        for (final sample in item.items.take(5))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _PreviewFavoriteItem(item: sample),
          ),
      ],
    );
  }
}

class _PreviewFavoriteItem extends StatelessWidget {
  const _PreviewFavoriteItem({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = _mapString(item, 'title');
    final url = _mapString(item, 'url') ?? '-';
    final exists = item['exists'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          exists ? '已存在' : '预计新增',
          style: theme.textTheme.labelMedium?.copyWith(
            color: exists ? cs.onSurfaceVariant : cs.primary,
          ),
        ),
        if (title != null) ...[
          const SizedBox(height: 4),
          Text(title, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: 4),
        SelectableText(
          url,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

Future<void> _updateFavoritesSyncSetting(
  BuildContext context,
  WidgetRef ref, {
  required String key,
  required Object value,
}) async {
  try {
    await ref
        .read(systemSettingsProvider.notifier)
        .updateSetting(key, value, category: 'favorites_sync');
    ref.invalidate(favoritesSyncStatusProvider);
    if (context.mounted) {
      Toast.show(context, '收藏同步参数已更新');
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '更新收藏同步参数失败'),
        isError: true,
      );
    }
  }
}

String _formatTime(String? value) {
  if (value == null) return '暂无';
  final time = DateTime.tryParse(value);
  return time == null
      ? '时间不可用'
      : DateFormat('MM-dd HH:mm').format(time.toLocal());
}

String? _mapString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

String _runStatusLabel(String status) {
  return switch (status) {
    'success' || 'ok' => '成功',
    'running' => '运行中',
    'error' || 'failed' => '失败',
    'partial_success' => '部分失败',
    'skipped' => '已跳过',
    _ => status,
  };
}

String _platformStateLabel(FavoritesPlatformStatus status) {
  if (!status.available) return '不可用';
  if (!status.enabled) return '未启用';
  if (status.authenticated == false) return '未认证';
  if (status.authenticated == null) return '暂时无法检测';
  return '可同步';
}
