import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
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
    this.contentId,
    this.needsAttention = false,
  });

  const ContentActionResult.success(
    String message, {
    String? runId,
    int? contentId,
    bool needsAttention = false,
  }) : this._(
         ok: true,
         message: message,
         runId: runId,
         contentId: contentId,
         needsAttention: needsAttention,
       );

  const ContentActionResult.failure(String message)
    : this._(ok: false, message: message);

  final bool ok;
  final String message;
  final String? runId;
  final int? contentId;
  final bool needsAttention;
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
      if (error is FormatException) {
        return ContentActionResult.failure('服务响应无效：${error.message}');
      }
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

  String _requiredRunIdOf(Object? data) {
    final runId = _runIdOf(data);
    if (runId == null) {
      throw const FormatException('动作响应缺少 run_id');
    }
    return runId;
  }

  int? _contentIdOf(Object? data) {
    if (data is! Map) return null;
    final value = data['content_id'] ?? data['id'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  int? _contentIdFromError(Object error) {
    if (error is! DioException || error.response?.data is! Map) return null;
    return _contentIdOf(error.response!.data);
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
    String? tagsText,
    String source = 'app',
    String? layoutTypeOverride,
    String? note,
    Map<String, dynamic>? clientContext,
  }) {
    return _run(0, 'create_share', () async {
      try {
        final response = await ref
            .read(apiClientProvider)
            .post(
              '/shares',
              data: {
                'url': url,
                'tags': tags,
                'tags_text': tagsText,
                'is_nsfw': isNsfw,
                'source': source,
                'layout_type_override': layoutTypeOverride,
                'note': note,
                'client_context': clientContext,
              },
            );
        ref.invalidate(collectionProvider);
        return ContentActionResult.success(
          '已保存内容，后台将继续解析',
          contentId: _contentIdOf(response.data),
        );
      } catch (error) {
        final info = parseApiErrorInfo(error);
        final contentId = _contentIdFromError(error);
        if (info.code == 'parse_queue_unavailable' && contentId != null) {
          ref.invalidate(collectionProvider);
          return ContentActionResult.success(
            '内容已保存，但解析任务暂未入队',
            contentId: contentId,
            needsAttention: true,
          );
        }
        rethrow;
      }
    });
  }

  /// 直接保存用户提供的原始文本，不经过网页解析。
  Future<ContentActionResult> createText({
    required String text,
    required List<String> tags,
    required bool isNsfw,
    String? title,
    String? tagsText,
    String source = 'manual_text',
    String? note,
    Map<String, dynamic>? clientContext,
  }) {
    return _run(0, 'create_text', () async {
      final response = await ref
          .read(apiClientProvider)
          .post(
            '/captures/text',
            data: {
              'text': text,
              'title': title,
              'tags': tags,
              'tags_text': tagsText,
              'source': source,
              'note': note,
              'client_context': clientContext,
              'is_nsfw': isNsfw,
            },
          );
      ref.invalidate(collectionProvider);
      return ContentActionResult.success(
        '已保存文本，可在收藏库中继续整理',
        contentId: _contentIdOf(response.data),
      );
    });
  }

  /// 上传并归档用户选择的原始文件。
  Future<ContentActionResult> createFile({
    required XFile file,
    required List<String> tags,
    required bool isNsfw,
    String? title,
    String source = 'manual_upload',
    String? note,
  }) {
    return _run(0, 'create_file', () async {
      final length = await file.length();
      final response = await ref
          .read(apiClientProvider)
          .post(
            '/captures/file',
            data: FormData.fromMap({
              'upload': MultipartFile.fromStream(
                () => file.openRead(),
                length,
                filename: file.name,
                contentType: file.mimeType == null
                    ? null
                    : DioMediaType.parse(file.mimeType!),
              ),
              if (title != null && title.trim().isNotEmpty)
                'title': title.trim(),
              if (tags.isNotEmpty) 'tags_text': tags.join(','),
              'source': source,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
              'is_nsfw': isNsfw,
            }),
          );
      ref.invalidate(collectionProvider);
      return ContentActionResult.success(
        '已归档原始文件',
        contentId: _contentIdOf(response.data),
      );
    });
  }

  /// 把一次系统分享中的多个文件作为同一个内容对象归档。
  Future<ContentActionResult> createFiles({
    required List<XFile> files,
    required List<String> tags,
    required bool isNsfw,
    String? title,
    String source = 'manual_upload',
    String? note,
    Map<String, dynamic>? clientContext,
  }) {
    if (files.isEmpty) {
      return Future.value(const ContentActionResult.failure('请选择要归档的文件'));
    }
    return _run(0, 'create_files', () async {
      final uploads = <MultipartFile>[];
      for (final file in files) {
        final length = await file.length();
        uploads.add(
          MultipartFile.fromStream(
            () => file.openRead(),
            length,
            filename: file.name,
            contentType: file.mimeType == null
                ? null
                : DioMediaType.parse(file.mimeType!),
          ),
        );
      }
      final form = FormData();
      form.files.addAll(uploads.map((upload) => MapEntry('uploads', upload)));
      if (title != null && title.trim().isNotEmpty) {
        form.fields.add(MapEntry('title', title.trim()));
      }
      if (tags.isNotEmpty) {
        form.fields.add(MapEntry('tags_text', tags.join(',')));
      }
      form.fields.add(MapEntry('source', source));
      if (note != null && note.trim().isNotEmpty) {
        form.fields.add(MapEntry('note', note.trim()));
      }
      if (clientContext != null) {
        form.fields.add(
          MapEntry('client_context_json', jsonEncode(clientContext)),
        );
      }
      form.fields.add(MapEntry('is_nsfw', isNsfw.toString()));
      final response = await ref
          .read(apiClientProvider)
          .post('/captures/files', data: form);
      ref.invalidate(collectionProvider);
      return ContentActionResult.success(
        files.length == 1 ? '已归档原始文件' : '已归档 ${files.length} 个共享文件',
        contentId: _contentIdOf(response.data),
      );
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
        runId: _requiredRunIdOf(response.data),
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

  /// 逐字段处理重新解析与人工修订之间的冲突。
  Future<ContentActionResult> resolveParseCandidate(
    int contentId, {
    required String field,
    required String action,
    String? mergedValue,
  }) {
    return _run(contentId, 'resolve_parse_candidate_$field', () async {
      await ref
          .read(apiClientProvider)
          .post(
            '/contents/$contentId/parse-candidate/resolve',
            data: {
              'field': field,
              'action': action,
              if (action == 'merge') 'merged_value': mergedValue,
            },
          );
      _invalidateDetail(contentId);
      ref.invalidate(collectionProvider);
      return ContentActionResult.success(switch (action) {
        'accept_parsed' => '已采用新解析结果',
        'keep_current' => '已保留人工版本',
        _ => '已保存合并版本',
      });
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
            '摘要已生成',
            runId: _requiredRunIdOf(response.data),
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
            lastRunId = _requiredRunIdOf(response.data);
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
            '巡逻评分已完成',
            runId: _requiredRunIdOf(response.data),
          );
      }
    });
  }
}
