import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../settings/utils/setting_value.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/toast.dart';
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
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              _SyncOverviewCard(status: status),
              const SizedBox(height: 16),
              _PlatformStatusGrid(platforms: status.platforms),
              const SizedBox(height: 16),
              _SyncCommandBar(status: status),
              const SizedBox(height: 16),
              _SyncPolicyCard(status: status),
              const SizedBox(height: 24),
              _RecentRunsList(runs: status.recentRuns),
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
              Text('收藏同步状态加载失败: $error'),
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
              ? '连接并启用平台，开始同步收藏'
              : '已启用 ${status.enabledPlatforms.length} 个平台',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${status.running ? '调度服务已启动' : '调度服务未启动'} · 最近同步 ${_formatTime(status.lastSyncAt)}',
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
    return ExpansionTile(
      title: const Text('同步策略'),
      tilePadding: EdgeInsets.zero,
      children: [
        settings.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => const Text('策略读取失败，请刷新后重试'),
          data: (values) => Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
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
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许手动同步未启用的平台'),
                subtitle: const Text('每次同步仍需预览并确认'),
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
        _PolicyStringControlRow(
          label: '重复内容',
          value: status.duplicateStrategy,
          options: const {'merge': '合并来源', 'skip': '跳过'},
          description: _duplicateStrategyDescription(status.duplicateStrategy),
          onChanged: (value) => _updateFavoritesSyncSetting(
            context,
            ref,
            key: 'favorites_sync_duplicate_strategy',
            value: value,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('首次从最新一页开始同步。远端取消收藏后，本地内容仍保留。'),
        ),
      ],
    );
  }
}

class _PolicyStringControlRow extends StatelessWidget {
  const _PolicyStringControlRow({
    required this.label,
    required this.value,
    required this.options,
    required this.description,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final String description;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final normalizedValue = options.containsKey(value)
        ? value
        : options.keys.first;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.difference_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          DropdownButton<String>(
            value: normalizedValue,
            underline: const SizedBox.shrink(),
            items: [
              for (final entry in options.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (next) {
              if (next != null && next != normalizedValue) {
                onChanged(next);
              }
            },
          ),
        ],
      ),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final options = _withCurrentValue(values, value);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DropdownButton<int>(
            value: value,
            underline: const SizedBox.shrink(),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text('$option $suffix')),
            ],
            onChanged: (next) {
              if (next != null && next != value) {
                onChanged(next);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SyncCommandBar extends ConsumerWidget {
  const _SyncCommandBar({required this.status});

  final FavoritesSyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _triggerWithPreview(context, ref),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('同步全部'),
        ),
        OutlinedButton.icon(
          onPressed: () => _showPreview(context, ref),
          icon: const Icon(Icons.manage_search_rounded),
          label: const Text('预览同步'),
        ),
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(favoritesSyncStatusProvider),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('刷新状态'),
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

    return Column(
      children: [
        for (final platform in platforms) ...[
          _PlatformStatusCard(status: platform),
          const Divider(height: 24),
        ],
      ],
    );
  }
}

class _PlatformStatusCard extends ConsumerWidget {
  const _PlatformStatusCard({required this.status});

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
        Row(
          children: [
            Icon(_platformIcon(status.platform), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _platformLabel(status.platform),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Switch.adaptive(
              value: status.enabled,
              onChanged: settings.hasValue
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
          ],
        ),
        Text(
          !status.authenticated ? '连接账号后可同步收藏' : _platformStateLabel(status),
        ),
        if (!status.available)
          Text(
            status.statusError?['error_hint']?.toString() ??
                '暂时无法检查账号，请到账号页重新检查',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!status.authenticated || !status.available)
              FilledButton.tonal(
                onPressed: () => context.push('/accounts/${status.platform}'),
                child: const Text('连接 / 检查账号'),
              )
            else ...[
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
            DropdownButton<int>(
              value: status.ratePerMinute.round(),
              underline: const SizedBox.shrink(),
              items: [
                for (final rate in _withCurrentValue(const [
                  1,
                  3,
                  5,
                  10,
                  20,
                ], status.ratePerMinute.round()))
                  DropdownMenuItem(value: rate, child: Text('$rate 条/分钟')),
              ],
              onChanged: (value) {
                if (value != null) {
                  _updateFavoritesSyncSetting(
                    context,
                    ref,
                    key: 'favorites_sync_rate_${status.platform}',
                    value: value,
                  );
                }
              },
            ),
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
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppShape.cardBorder,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              for (final entry in runs.take(8).indexed) ...[
                _RunTile(run: entry.$2),
                if (entry.$1 < runs.take(8).length - 1)
                  const Divider(height: 1),
              ],
            ],
          ),
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

    return ListTile(
      leading: Icon(
        isError ? Icons.error_outline_rounded : Icons.task_alt_rounded,
        color: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        '${_runStatusLabel(status)} · ${_runString(run, 'scope') == 'all' ? '全部平台' : _platformLabel(_runString(run, 'scope') ?? '')}',
      ),
      subtitle: Text(
        [
          if (_runString(run, 'started_at') != null)
            _formatTime(_runString(run, 'started_at')),
          if (error != null) '错误: $error',
        ].join('\n'),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: isError && runId != null
          ? OutlinedButton.icon(
              onPressed: () => _retryRun(context, ref, runId),
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('重试'),
            )
          : null,
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
      padding: const EdgeInsets.all(20),
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
  final cs = theme.colorScheme;
  final label = preview.platform == 'all'
      ? '全平台'
      : _platformLabel(preview.platform);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(confirmMode ? '确认同步 $label 收藏' : '$label 收藏同步预览'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Text('拉取 ${preview.fetched}'),
                  Text('预计新增 ${preview.estimatedNew}'),
                  Text('已存在 ${preview.existing}'),
                  Text('跳过 ${preview.skipped}'),
                ],
              ),
              const SizedBox(height: 14),
              for (final item in preview.platforms)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PreviewPlatformSection(item: item),
                ),
              Text(
                '确认前不会导入内容或改变同步进度。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
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
    final failed = item.status == 'failed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          failed
              ? '${_platformLabel(item.platform)}: ${item.errorHint ?? item.error ?? '预览失败'}'
              : '${_platformLabel(item.platform)}: 新增 ${item.estimatedNew}，重复 ${item.existing}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: failed ? cs.error : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (!failed && item.items.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '候选样本',
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final sample in item.items.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _PreviewFavoriteItem(item: sample),
            ),
        ],
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: AppShape.cardMediaBorder,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              exists ? Icons.content_copy_rounded : Icons.add_circle_rounded,
              size: 18,
              color: exists ? cs.outline : cs.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  SelectableText(
                    url,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              exists ? '已存在' : '预计新增',
              style: theme.textTheme.labelMedium?.copyWith(
                color: exists ? cs.outline : cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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

String _duplicateStrategyDescription(String strategy) {
  return switch (strategy) {
    'skip' => '已保存的内容不再导入。',
    _ => '为已保存的内容补充收藏来源。',
  };
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
    _ => platform,
  };
}

IconData _platformIcon(String platform) {
  return switch (platform) {
    'zhihu' => Icons.question_answer_rounded,
    'xiaohongshu' => Icons.menu_book_rounded,
    'twitter' => Icons.alternate_email_rounded,
    _ => Icons.bookmarks_rounded,
  };
}

String _platformStateLabel(FavoritesPlatformStatus status) {
  if (!status.available) return '不可用';
  if (!status.enabled) return '未启用';
  if (!status.authenticated) return '未认证';
  return '可同步';
}
