import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../models/processing_status.dart';
import 'collection_provider.dart';

part 'content_actions_controller.g.dart';

/// 一次内容写操作的结果。
///
/// UI 只消费本类型，不解析 HTTP 响应体。`runId` 存在时表示后台运行已受理，
/// 最终状态需要通过任务页或 SSE 事件确认——"已受理"不等于"已成功"。
class ContentActionResult {
  const ContentActionResult._({
    required this.ok,
    required this.message,
    this.runId,
  });

  const ContentActionResult.success(String message, {String? runId})
    : this._(ok: true, message: message, runId: runId);

  const ContentActionResult.failure(String message)
    : this._(ok: false, message: message);

  final bool ok;
  final String message;
  final String? runId;
}

/// 正在执行的内容写操作集合。
///
/// key 形如 `12:generate_summary`，UI 据此禁用按钮并显示进度，
/// 避免重复提交同一个有外部副作用的动作。
typedef ContentActionPending = Set<String>;

String _pendingKey(int contentId, String action) => '$contentId:$action';

/// 内容写操作的统一控制层。
///
/// 收藏库与内容详情的所有写操作都必须经过这里，Widget 不直接调用
/// `apiClientProvider`。这样重试、错误文案、run 追踪和 provider 失效
/// 只有一处实现。
@Riverpod(keepAlive: true)
class ContentActions extends _$ContentActions {
  @override
  ContentActionPending build() => const <String>{};

  bool isPending(int contentId, String action) =>
      state.contains(_pendingKey(contentId, action));

  /// 某条内容是否有任何进行中的写操作。
  bool hasPendingFor(int contentId) =>
      state.any((key) => key.startsWith('$contentId:'));

  Future<ContentActionResult> _run(
    int contentId,
    String action,
    Future<ContentActionResult> Function() body,
  ) async {
    final key = _pendingKey(contentId, action);
    if (state.contains(key)) {
      return const ContentActionResult.failure('该操作正在执行中');
    }
    state = {...state, key};
    try {
      return await body();
    } catch (error) {
      return ContentActionResult.failure(
        formatApiErrorMessage(error, fallbackMessage: '操作失败'),
      );
    } finally {
      state = {...state}..remove(key);
    }
  }

  String? _runIdOf(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    final value = data['run_id']?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  void _invalidateDetail(int contentId) {
    ref.invalidate(contentDetailProvider(contentId));
    ref.invalidate(contentProcessingStatusProvider(contentId));
  }

  // --- 内容级动作 ---

  /// 从统一捕获入口保存分享链接。
  Future<ContentActionResult> createShare({
    required String url,
    required List<String> tags,
    required bool isNsfw,
  }) {
    return _run(0, 'create_share', () async {
      await ref
          .read(apiClientProvider)
          .post(
            '/shares',
            data: {
              'url': url,
              'tags': tags,
              'is_nsfw': isNsfw,
              'source': 'app',
            },
          );
      ref.invalidate(collectionProvider);
      return const ContentActionResult.success('已保存内容，后台将继续解析');
    });
  }

  /// 重新解析。异步执行，返回可观察的 run_id。
  Future<ContentActionResult> reParse(int contentId) {
    return _run(contentId, 'reparse', () async {
      final response = await ref
          .read(apiClientProvider)
          .post('/contents/$contentId/re-parse');
      _invalidateDetail(contentId);
      return ContentActionResult.success(
        '已触发重新解析',
        runId: _runIdOf(response.data),
      );
    });
  }

  Future<ContentActionResult> deleteContent(int contentId) {
    return _run(contentId, 'delete', () async {
      await ref.read(apiClientProvider).delete('/contents/$contentId');
      ref.invalidate(collectionProvider);
      return const ContentActionResult.success('已删除内容');
    });
  }

  /// 人工修订内容字段。只提交调用方显式给出的字段。
  Future<ContentActionResult> updateContent(
    int contentId,
    Map<String, dynamic> patch,
  ) {
    return _run(contentId, 'update', () async {
      if (patch.isEmpty) {
        return const ContentActionResult.failure('没有需要保存的修改');
      }
      await ref
          .read(apiClientProvider)
          .patch('/contents/$contentId', data: patch);
      _invalidateDetail(contentId);
      ref.invalidate(collectionProvider);
      return const ContentActionResult.success('内容已更新');
    });
  }

  /// 覆盖或清除模板（`layout_type_override`）。
  ///
  /// 传 `null` 表示恢复系统判定。人工选择的模板不会被重新解析静默覆盖。
  Future<ContentActionResult> setLayoutOverride(
    int contentId,
    String? layoutType,
  ) {
    return _run(contentId, 'layout_override', () async {
      await ref
          .read(apiClientProvider)
          .patch(
            '/contents/$contentId',
            data: {'layout_type_override': layoutType},
          );
      _invalidateDetail(contentId);
      ref.invalidate(collectionProvider);
      return ContentActionResult.success(
        layoutType == null ? '已恢复系统判定的模板' : '已切换模板',
      );
    });
  }

  // --- 后处理阶段动作 ---

  /// 执行一个由后端声明的阶段动作。
  ///
  /// 动作种类和目标对象都来自 `/contents/{id}/processing-status` 的
  /// typed contract，前端不根据状态字符串推断可执行动作。
  Future<ContentActionResult> runStageAction(
    int contentId,
    ProcessingStageAction action,
  ) {
    return _run(contentId, action.kind.name, () async {
      final dio = ref.read(apiClientProvider);
      switch (action.kind) {
        case ProcessingActionKind.generateSummary:
          final response = await dio.post(
            '/contents/$contentId/generate-summary',
            queryParameters: {'force': true},
          );
          _invalidateDetail(contentId);
          return ContentActionResult.success(
            '已开始生成摘要',
            runId: _runIdOf(response.data),
          );

        case ProcessingActionKind.rebuildSemanticIndex:
          final response = await dio.post(
            '/search/semantic/reindex',
            data: {
              'scope': 'single',
              'content_id': contentId,
              'dry_run': false,
            },
          );
          _invalidateDetail(contentId);
          return ContentActionResult.success(
            '已调度语义索引重建',
            runId: _runIdOf(response.data),
          );

        case ProcessingActionKind.retrySemanticChunk:
          if (action.targetIds.isEmpty) {
            return const ContentActionResult.failure('没有可重试的语义分块');
          }
          String? lastRunId;
          for (final id in action.targetIds) {
            final response = await dio.post(
              '/search/semantic/embeddings/$id/retry',
            );
            lastRunId = _runIdOf(response.data) ?? lastRunId;
          }
          _invalidateDetail(contentId);
          return ContentActionResult.success(
            '已重试 ${action.targetIds.length} 个语义分块',
            runId: lastRunId,
          );

        case ProcessingActionKind.retryDistributionItem:
          if (action.targetIds.isEmpty) {
            return const ContentActionResult.failure('没有可重试的分发项');
          }
          await dio.post(
            '/distribution-queue/batch-retry',
            data: {'item_ids': action.targetIds},
          );
          _invalidateDetail(contentId);
          return ContentActionResult.success(
            '已重试 ${action.targetIds.length} 条分发项',
          );

        case ProcessingActionKind.rematchDistribution:
          await dio.post(
            '/distribution-queue/enqueue/$contentId',
            data: {'force': true},
          );
          _invalidateDetail(contentId);
          return const ContentActionResult.success('已重新匹配分发规则');

        case ProcessingActionKind.patrolScore:
          final response = await dio.post('/contents/$contentId/patrol-score');
          _invalidateDetail(contentId);
          return ContentActionResult.success(
            '已触发巡逻评分',
            runId: _runIdOf(response.data),
          );
      }
    });
  }
}
