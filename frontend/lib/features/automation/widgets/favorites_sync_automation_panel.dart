import '../../../core/widgets/app_setting_group.dart';
import '../../../core/layout/app_page_body.dart';

import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/metadata_wrap.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../settings/utils/setting_value.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
import '../../../core/widgets/adaptive_form_dialog.dart';
import '../../../core/widgets/app_filter_menu.dart';
import '../../../theme/design_tokens.dart';
import '../../settings/providers/favorites_sync_provider.dart';
import '../../settings/providers/settings_provider.dart';

class FavoritesSyncAutomationPanel extends ConsumerStatefulWidget {
  const FavoritesSyncAutomationPanel({super.key, this.highlightRunId});

  final String? highlightRunId;

  @override
  ConsumerState<FavoritesSyncAutomationPanel> createState() =>
      _FavoritesSyncAutomationPanelState();
}

class _FavoritesSyncAutomationPanelState
    extends ConsumerState<FavoritesSyncAutomationPanel> {
  String? _openedRunId;

  @override
  void didUpdateWidget(FavoritesSyncAutomationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightRunId != widget.highlightRunId) {
      _openedRunId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(favoritesSyncStatusProvider);

    return statusAsync.when(
      data: (status) {
        _openHighlightedRunIfReady(status.recentRuns);
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(favoritesSyncStatusProvider),
          child: AppPageBody(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              children: [
                _SyncOverviewCard(status: status),
                const SizedBox(height: 16),
                _SyncCommandBar(enabled: status.enabledPlatforms.isNotEmpty),
                const SizedBox(height: 24),
                _PlatformStatusGrid(platforms: status.platforms),
                const SizedBox(height: 24),
                _SyncPolicyCard(status: status),
                const SizedBox(height: 24),
                _RecentRunsList(runs: status.recentRuns),
              ],
            ),
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
              Text(formatApiErrorMessage(error, fallbackMessage: '收藏同步状态加载失败')),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(favoritesSyncStatusProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openHighlightedRunIfReady(List<Map<String, dynamic>> runs) {
    final highlightRunId = widget.highlightRunId;
    if (highlightRunId == null ||
        highlightRunId.isEmpty ||
        _openedRunId == highlightRunId) {
      return;
    }
    Map<String, dynamic>? matchedRun;
    for (final run in runs) {
      if (_runString(run, 'run_id') == highlightRunId) {
        matchedRun = run;
        break;
      }
    }
    if (matchedRun == null) return;

    _openedRunId = highlightRunId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/tasks/$highlightRunId');
    });
  }
}

class _SyncOverviewCard extends StatelessWidget {
  const _SyncOverviewCard({required this.status});

  final FavoritesSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          status.enabledPlatforms.isEmpty
              ? '未启用平台'
              : '已启用 ${status.enabledPlatforms.length} 个平台',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        MetadataWrap(
          items: [
            status.running ? '调度服务已启动' : '调度服务未启动',
            '最近同步 ${_formatTime(status.lastSyncAt)}',
          ],
          style: theme.textTheme.bodySmall,
        ),
      ],
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
              for (final platform in status.platforms.where(
                (p) => p.capabilities.supported,
              ))
                _PolicyControlRow(
                  label: '${_platformLabel(platform.platform)} 同步速率',
                  value: platform.ratePerMinute.round(),
                  values: const [1, 3, 5, 10, 20],
                  suffix: '条/分钟',
                  onChanged: (value) => _updateFavoritesSyncSetting(
                    context,
                    ref,
                    key: 'favorites_sync_rate_${platform.platform}',
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
      for (final option in _withCurrentValue(values, value))
        '$option': '$option $suffix',
    },
    onSelected: (next) => onChanged(int.parse(next)),
  );
}

class _SyncCommandBar extends ConsumerWidget {
  const _SyncCommandBar({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.tonalIcon(
          onPressed: enabled ? () => _triggerWithPreview(context, ref) : null,
          icon: const Icon(Icons.sync_rounded),
          label: const Text('同步全部'),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? () => _showPreview(context, ref) : null,
          icon: const Icon(Icons.manage_search_rounded),
          label: const Text('预览同步'),
        ),
      ],
    );
  }
}

class _PlatformStatusGrid extends StatelessWidget {
  const _PlatformStatusGrid({required this.platforms});

  final List<FavoritesPlatformStatus> platforms;

  @override
  Widget build(BuildContext context) {
    if (platforms.isEmpty) {
      return const _EmptyPanel(message: '暂无可用收藏同步平台');
    }

    return AppSettingGroup(
      children: [
        for (final platform in platforms)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            title: Text(_platformLabel(platform.platform)),
            subtitle: Text(_platformStateLabel(platform)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go('/accounts/${platform.platform}?from=sync'),
          ),
      ],
    );
  }
}

class AccountFavoritesSyncControls extends ConsumerWidget {
  const AccountFavoritesSyncControls({super.key, required this.status});

  final FavoritesPlatformStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(systemSettingsProvider);
    final enabled =
        ref.watch(favoritesSyncStatusProvider).value?.enabledPlatforms ??
        const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(
            borderRadius: AppShape.cardMediaBorder,
          ),
          title: Text('同步收藏', style: Theme.of(context).textTheme.titleMedium),
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
        if (!status.capabilities.supported || status.enabled)
          Text(
            !status.capabilities.supported
                ? '暂未接入收藏同步'
                : !status.authenticated
                ? '连接账号后可同步收藏'
                : _platformStateLabel(status),
          ),
        Text(status.capabilities.scope),
        if (status.capabilities.limitation != null)
          Text(status.capabilities.limitation!),
        if (!status.available && status.capabilities.supported)
          Text(
            status.statusError?['error_hint']?.toString() ??
                status.error ??
                '暂时无法检查账号，请到账号页重新检查',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (status.capabilities.supported &&
                status.authenticated &&
                status.available) ...[
              OutlinedButton(
                onPressed: () =>
                    _showPreview(context, ref, platform: status.platform),
                child: const Text('预览'),
              ),
              FilledButton.tonal(
                onPressed: () => _triggerWithPreview(
                  context,
                  ref,
                  platform: status.platform,
                ),
                child: const Text('同步'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RecentRunsList extends ConsumerWidget {
  const _RecentRunsList({required this.runs});

  final List<Map<String, dynamic>> runs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (runs.isEmpty) {
      return const _EmptyPanel(message: '暂无同步运行记录');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同步运行记录',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        AppSettingGroup(
          children: [for (final run in runs.take(8)) _RunTile(run: run)],
        ),
      ],
    );
  }
}

class _RunTile extends ConsumerWidget {
  const _RunTile({required this.run});

  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = _runString(run, 'status') ?? 'unknown';
    final runId = _runString(run, 'run_id');
    final isError = status == 'error';
    final error = _runString(run, 'error');

    final theme = Theme.of(context);
    final statusLabel =
        status == 'success' &&
            run['result'] is Map &&
            (run['result'] as Map)['platform_count'] == 0
        ? '未执行平台同步'
        : _runStatusLabel(status);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Text(
        _runString(run, 'scope') == 'all'
            ? '全部平台'
            : _platformLabel(_runString(run, 'scope') ?? ''),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MetadataWrap(
            items: [
              statusLabel,
              if (_runString(run, 'started_at') != null)
                _formatTime(_runString(run, 'started_at')),
            ],
          ),
          if (error != null)
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          if (isError && runId != null)
            TextButton.icon(
              onPressed: () => _retryRun(context, ref, runId),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('重试'),
            ),
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

Future<void> _showPreview(
  BuildContext context,
  WidgetRef ref, {
  String? platform,
}) async {
  try {
    final preview = await ref
        .read(favoritesSyncActionsProvider)
        .previewSync(platform: platform);
    if (!context.mounted) return;
    await _showPreviewDialog(context, preview, confirmMode: false);
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '预览同步失败'),
        isError: true,
      );
    }
  }
}

Future<void> _triggerWithPreview(
  BuildContext context,
  WidgetRef ref, {
  String? platform,
}) async {
  try {
    final actions = ref.read(favoritesSyncActionsProvider);
    final preview = await actions.previewSync(platform: platform);
    if (!context.mounted) return;
    final confirmed = await _showPreviewDialog(
      context,
      preview,
      confirmMode: true,
    );
    if (!confirmed || !context.mounted) return;

    final runId = await actions.triggerSync(platform: platform);
    if (context.mounted) {
      Toast.show(
        context,
        '已触发 ${platform == null ? '全平台' : _platformLabel(platform)} 同步${runId == null ? '' : ' #${_shortId(runId)}'}',
      );
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '触发同步失败'),
        isError: true,
      );
    }
  }
}

Future<bool> _showPreviewDialog(
  BuildContext context,
  FavoritesSyncPreview preview, {
  required bool confirmMode,
}) async {
  final theme = Theme.of(context);
  final label = preview.platform == 'all'
      ? '全平台'
      : _platformLabel(preview.platform);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AdaptiveFormDialog(
      title: confirmMode ? '同步$label收藏' : '$label收藏同步预览',
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
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(confirmMode ? '取消' : '关闭'),
          ),
          if (confirmMode)
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认同步'),
            ),
        ],
      ),
    ),
  );
  return result == true;
}

class _PreviewPlatformSection extends StatelessWidget {
  const _PreviewPlatformSection({required this.item});
  final FavoritesSyncPlatformPreview item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = Text(
      _platformLabel(item.platform),
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

Future<void> _retryRun(
  BuildContext context,
  WidgetRef ref,
  String runId,
) async {
  try {
    final retryRunId = await ref
        .read(favoritesSyncActionsProvider)
        .retryRun(runId);
    if (context.mounted) {
      Toast.show(
        context,
        '已重新触发同步${retryRunId == null ? '' : ' #${_shortId(retryRunId)}'}',
      );
    }
  } catch (e) {
    if (context.mounted) {
      Toast.show(
        context,
        formatApiErrorMessage(e, fallbackMessage: '重试同步失败'),
        isError: true,
      );
    }
  }
}

String? _mapString(Map<String, dynamic> item, String key) {
  final value = item[key];
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

List<int> _withCurrentValue(List<int> values, int current) {
  final set = {current, ...values}.toList()..sort();
  return set;
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

String? _runString(Map<String, dynamic> run, String key) {
  final value = run[key];
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

String _shortId(String? runId) {
  if (runId == null || runId.isEmpty) return '-';
  return runId.length > 8 ? runId.substring(0, 8) : runId;
}

String _runStatusLabel(String status) {
  return switch (status) {
    'success' => '成功',
    'running' => '运行中',
    'error' => '失败',
    _ => status,
  };
}

String _platformLabel(String platform) {
  return switch (platform) {
    'zhihu' => '知乎',
    'xiaohongshu' => '小红书',
    'twitter' => 'Twitter / X',
    'bilibili' => 'Bilibili',
    'weibo' => '微博',
    _ => platform,
  };
}

String _platformStateLabel(FavoritesPlatformStatus status) {
  if (!status.available) return '不可用';
  if (!status.enabled) return '未启用';
  if (!status.authenticated) return '未认证';
  return '可同步';
}
