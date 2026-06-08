import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/frosted_app_bar.dart';
import 'models/stats.dart';
import 'providers/dashboard_provider.dart';

class TaskResultPage extends ConsumerWidget {
  const TaskResultPage({super.key, required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runAsync = ref.watch(backgroundTaskRunProvider(runId));
    return Scaffold(
      appBar: FrostedAppBar(
        title: const Text('任务结果'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(backgroundTaskRunProvider(runId)),
          ),
        ],
      ),
      body: runAsync.when(
        data: (run) => _TaskResultBody(run: run),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 44,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text('任务结果加载失败: $error'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      ref.invalidate(backgroundTaskRunProvider(runId)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskResultBody extends StatelessWidget {
  const _TaskResultBody({required this.run});

  final BackgroundTaskRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(colorScheme, run.status);
    final metadata = run.metadata;
    final result = run.result ?? const <String, dynamic>{};
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_statusIcon(run.status), color: statusColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        run.task,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _statusLabel(run.status),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _DetailLine(label: 'Run ID', value: run.runId),
                _DetailLine(
                  label: '触发来源',
                  value: _metadataValue(metadata, 'trigger'),
                ),
                _DetailLine(
                  label: '关联平台',
                  value: _metadataValue(metadata, 'platform'),
                ),
                _DetailLine(label: '关联对象', value: _relatedObject(metadata)),
                if (run.startedAt != null)
                  _DetailLine(
                    label: '开始时间',
                    value: run.startedAt!.toLocal().toString(),
                  ),
                if (run.finishedAt != null)
                  _DetailLine(
                    label: '结束时间',
                    value: run.finishedAt!.toLocal().toString(),
                  ),
                if (run.error != null && run.error!.isNotEmpty)
                  _DetailLine(label: '错误原因', value: run.error!),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (metadata.isNotEmpty)
          _JsonSection(title: 'Metadata', data: metadata),
        if (metadata.isNotEmpty && result.isNotEmpty)
          const SizedBox(height: 16),
        if (result.isNotEmpty) _JsonSection(title: 'Result', data: result),
        if (result.isEmpty && metadata.isEmpty) ...[
          const SizedBox(height: 24),
          Text(
            '暂无额外 payload。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _JsonSection extends StatelessWidget {
  const _JsonSection({required this.title, required this.data});

  final String title;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final encoder = const JsonEncoder.withIndent('  ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              encoder.convert(data),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

String _metadataValue(Map<String, dynamic> metadata, String key) {
  final value = metadata[key];
  return value == null ? '-' : value.toString();
}

String _relatedObject(Map<String, dynamic> metadata) {
  for (final key in ['content_id', 'source_id', 'target_id', 'scope', 'url']) {
    final value = metadata[key];
    if (value != null && value.toString().isNotEmpty) {
      return '$key=$value';
    }
  }
  return '-';
}

IconData _statusIcon(String status) {
  return switch (status) {
    'success' || 'ok' => Icons.task_alt_rounded,
    'running' => Icons.sync_rounded,
    'error' || 'failed' => Icons.error_outline_rounded,
    _ => Icons.info_outline_rounded,
  };
}

Color _statusColor(ColorScheme colorScheme, String status) {
  return switch (status) {
    'success' || 'ok' => Colors.green,
    'running' => colorScheme.primary,
    'error' || 'failed' => colorScheme.error,
    _ => colorScheme.onSurfaceVariant,
  };
}

String _statusLabel(String status) {
  return switch (status) {
    'success' || 'ok' => '成功',
    'running' => '运行中',
    'error' || 'failed' => '失败',
    _ => status,
  };
}
