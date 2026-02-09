import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/platform_constants.dart';
import '../../core/widgets/frosted_app_bar.dart';
import 'models/target_usage_info.dart';
import 'models/target_list_response.dart';
import 'providers/targets_provider.dart';

class TargetsManagementPage extends ConsumerStatefulWidget {
  const TargetsManagementPage({super.key});

  @override
  ConsumerState<TargetsManagementPage> createState() =>
      _TargetsManagementPageState();
}

class _TargetsManagementPageState
    extends ConsumerState<TargetsManagementPage> {
  String? _filterPlatform;
  bool? _filterEnabled;
  final Set<String> _testingTargets = {};  // Changed to Set to support multiple concurrent tests

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetsAsync = ref.watch(targetsProvider(
      platform: _filterPlatform,
      enabled: _filterEnabled,
    ));

    return Scaffold(
      appBar: FrostedAppBar(
        title: const Text('目标管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list_rounded),
            onPressed: _showFilterDialog,
            tooltip: '筛选',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(targetsProvider);
            },
            tooltip: '刷新',
          ),
        ],
      ),
      body: targetsAsync.when(
        data: (response) => _buildTargetsList(response),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('加载失败: $error'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.invalidate(targetsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTargetsList(TargetListResponse response) {
    final theme = Theme.of(context);
    final targets = response.targets;

    if (targets.isEmpty) {
      final hasFilters = _filterPlatform != null || _filterEnabled != null;
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.track_changes_rounded,
                size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              hasFilters ? '没有符合条件的目标' : '暂无目标',
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilters 
                  ? '尝试调整筛选条件或清除筛选'
                  : '在分发规则中添加目标后，它们将显示在这里',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _filterPlatform = null;
                    _filterEnabled = null;
                  });
                },
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('清除筛选'),
              ),
            ],
          ],
        ),
      );
    }

    // Group by platform
    final Map<String, List<TargetUsageInfo>> groupedTargets = {};
    for (final target in targets) {
      groupedTargets.putIfAbsent(target.targetPlatform, () => []);
      groupedTargets[target.targetPlatform]!.add(target);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: groupedTargets.entries.map((entry) {
        return _buildPlatformSection(entry.key, entry.value);
      }).toList(),
    );
  }

  Widget _buildPlatformSection(String platform, List<TargetUsageInfo> targets) {
    final theme = Theme.of(context);
    final platformIcon = platform == 'telegram'
        ? Icons.telegram
        : platform == 'qq'
            ? Icons.forum_rounded
            : Icons.share_rounded;
    final platformName = platform == 'telegram'
        ? 'Telegram'
        : platform == 'qq'
            ? 'QQ'
            : platform.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Icon(platformIcon, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                platformName,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${targets.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...targets
            .map((target) => _buildTargetCard(target))
            .toList()
            .animate(interval: 50.ms)
            .fadeIn(duration: 300.ms)
            .slideX(begin: 0.2, end: 0),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTargetCard(TargetUsageInfo target) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final targetKey = '${target.targetPlatform}:${target.targetId}';
    final isTesting = _testingTargets.contains(targetKey);  // Check if in Set

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showTargetDetails(target),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: target.enabled
                          ? colorScheme.primary.withValues(alpha: 0.1)
                          : colorScheme.outline.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      target.targetPlatform == 'telegram'
                          ? Icons.telegram
                          : Icons.forum_rounded,
                      size: 20,
                      color: target.enabled
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target.targetId,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (target.summary.isNotEmpty)
                          Text(
                            target.summary,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: colorScheme.outline),
                          ),
                      ],
                    ),
                  ),
                  if (!target.enabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.outline.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '已禁用',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    icon: Icons.rule_rounded,
                    label: '${target.ruleCount} 规则',
                    theme: theme,
                  ),
                  _buildInfoChip(
                    icon: Icons.send_rounded,
                    label: '${target.totalPushed} 推送',
                    theme: theme,
                  ),
                  if (target.lastPushedAt != null)
                    _buildInfoChip(
                      icon: Icons.access_time_rounded,
                      label: timeago.format(target.lastPushedAt!,
                          locale: 'zh_CN'),
                      theme: theme,
                    ),
                  if (target.renderConfig != null)
                    _buildInfoChip(
                      icon: Icons.palette_rounded,
                      label: '自定义渲染',
                      theme: theme,
                      color: colorScheme.tertiary,
                    ),
                  if (target.mergeForward)
                    _buildInfoChip(
                      icon: Icons.forward_to_inbox_rounded,
                      label: '合并转发',
                      theme: theme,
                      color: colorScheme.secondary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isTesting
                          ? null
                          : () => _testTargetConnection(target),
                      icon: isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering_rounded, size: 18),
                      label: Text(isTesting ? '测试中...' : '测试连接'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _showTargetDetails(target),
                    icon: const Icon(Icons.info_outline_rounded, size: 18),
                    label: const Text('详情'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required ThemeData theme,
    Color? color,
  }) {
    final chipColor = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: chipColor, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _testTargetConnection(TargetUsageInfo target) async {
    final targetKey = '${target.targetPlatform}:${target.targetId}';
    
    // Prevent duplicate requests
    if (_testingTargets.contains(targetKey)) {
      return;
    }
    
    setState(() {
      _testingTargets.add(targetKey);
    });

    try {
      final result = await ref.read(targetsProvider().notifier).testConnection(
            platform: target.targetPlatform,
            targetId: target.targetId,
          );

      if (!mounted) return;

      final status = result['status'] as String;
      final message = result['message'] as String;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                status == 'ok' ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: status == 'ok' ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('测试失败: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _testingTargets.remove(targetKey);
        });
      }
    }
  }

  void _showTargetDetails(TargetUsageInfo target) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _TargetDetailsSheet(target: target),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('筛选目标'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('平台'),
              trailing: DropdownButton<String?>(
                value: _filterPlatform,
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部')),
                  DropdownMenuItem(
                      value: PlatformConstants.telegram,
                      child: Text('Telegram')),
                  DropdownMenuItem(
                      value: PlatformConstants.qq, child: Text('QQ')),
                ],
                onChanged: (value) {
                  setState(() => _filterPlatform = value);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              title: const Text('状态'),
              trailing: DropdownButton<bool?>(
                value: _filterEnabled,
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部')),
                  DropdownMenuItem(value: true, child: Text('已启用')),
                  DropdownMenuItem(value: false, child: Text('已禁用')),
                ],
                onChanged: (value) {
                  setState(() => _filterEnabled = value);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _filterPlatform = null;
                _filterEnabled = null;
              });
              Navigator.pop(context);
            },
            child: const Text('重置'),
          ),
        ],
      ),
    );
  }
}

class _TargetDetailsSheet extends ConsumerWidget {
  const _TargetDetailsSheet({required this.target});

  final TargetUsageInfo target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      target.targetPlatform == PlatformConstants.telegram
                          ? Icons.telegram
                          : Icons.forum_rounded,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target.targetId,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (target.summary.isNotEmpty)
                          Text(
                            target.summary,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.outline),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildDetailSection(
                      '基本信息',
                      [
                        _DetailItem('平台', target.targetPlatform.toUpperCase()),
                        _DetailItem('目标 ID', target.targetId),
                        _DetailItem('状态', target.enabled ? '已启用' : '已禁用'),
                        if (target.summary.isNotEmpty)
                          _DetailItem('显示名称', target.summary),
                      ],
                      theme,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailSection(
                      '使用统计',
                      [
                        _DetailItem('使用规则数', '${target.ruleCount}'),
                        _DetailItem('总推送次数', '${target.totalPushed}'),
                        if (target.lastPushedAt != null)
                          _DetailItem(
                            '最后推送',
                            timeago.format(target.lastPushedAt!,
                                locale: 'zh_CN'),
                          ),
                      ],
                      theme,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailSection(
                      '关联规则',
                      target.ruleNames.asMap().entries.map((entry) {
                        return _DetailItem(
                          '规则 ${entry.key + 1}',
                          entry.value,
                        );
                      }).toList(),
                      theme,
                    ),
                    if (target.renderConfig != null) ...[
                      const SizedBox(height: 16),
                      _buildDetailSection(
                        '渲染配置',
                        [
                          _DetailItem('已自定义', '覆盖默认配置'),
                        ],
                        theme,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _batchDisable(context, ref),
                      icon: const Icon(Icons.block_rounded),
                      label: Text(target.enabled ? '批量禁用' : '批量启用'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailSection(
    String title,
    List<_DetailItem> items,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      item.label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.value,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Future<void> _batchDisable(BuildContext context, WidgetRef ref) async {
    final newState = !target.enabled;
    try {
      await ref.read(targetsProvider().notifier).batchUpdate(
            ruleIds: target.ruleIds,
            targetPlatform: target.targetPlatform,
            targetId: target.targetId,
            enabled: newState,
          );
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已在 ${target.ruleCount} 个规则中${newState ? "启用" : "禁用"}目标'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _DetailItem {
  final String label;
  final String value;

  _DetailItem(this.label, this.value);
}
