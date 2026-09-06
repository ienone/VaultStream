import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/knowledge_event.dart';

final knowledgeEventsProvider = FutureProvider.autoDispose
    .family<KnowledgeEventListResponse, int?>((ref, contentId) async {
      final response = await ref
          .read(apiClientProvider)
          .get(
            '/knowledge-events',
            queryParameters: {
              'page': 1,
              'size': 100,
              if (contentId != null) 'content_id': contentId,
            },
          );
      return KnowledgeEventListResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final activeKnowledgeEventsProvider =
    FutureProvider.autoDispose<KnowledgeEventListResponse>((ref) async {
      final response = await ref
          .read(apiClientProvider)
          .get(
            '/knowledge-events',
            queryParameters: {'page': 1, 'size': 100, 'status': 'active'},
          );
      return KnowledgeEventListResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final knowledgeEventDetailProvider = FutureProvider.autoDispose
    .family<KnowledgeEventDetail, int>((ref, eventId) async {
      final response = await ref
          .read(apiClientProvider)
          .get('/knowledge-events/$eventId');
      return KnowledgeEventDetail.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final knowledgeEventActionsProvider = Provider<KnowledgeEventActions>(
  KnowledgeEventActions.new,
);

class KnowledgeEventActions {
  KnowledgeEventActions(this.ref);

  final Ref ref;

  Future<KnowledgeEventDetail> createForContent({
    required int contentId,
    required String title,
    required String role,
    required String evidenceState,
  }) async {
    final response = await ref
        .read(apiClientProvider)
        .post(
          '/knowledge-events',
          data: {
            'title': title,
            'members': [
              {
                'content_id': contentId,
                'role': role,
                'evidence_state': evidenceState,
              },
            ],
          },
        );
    final event = _detail(response.data);
    _invalidate(event.id, contentId: contentId);
    return event;
  }

  Future<KnowledgeEventDetail> addContent({
    required int eventId,
    required int contentId,
    required String role,
    required String evidenceState,
    String? note,
  }) async {
    final response = await ref
        .read(apiClientProvider)
        .post(
          '/knowledge-events/$eventId/members',
          data: {
            'content_id': contentId,
            'role': role,
            'evidence_state': evidenceState,
            if (note != null) 'note': note,
          },
        );
    final event = _detail(response.data);
    _invalidate(eventId, contentId: contentId);
    return event;
  }

  Future<KnowledgeEventDetail> updateEvent(
    int eventId,
    Map<String, dynamic> changes,
  ) async {
    final response = await ref
        .read(apiClientProvider)
        .patch('/knowledge-events/$eventId', data: changes);
    final event = _detail(response.data);
    _invalidate(eventId);
    return event;
  }

  Future<KnowledgeEventDetail> updateMember({
    required int eventId,
    required int contentId,
    required Map<String, dynamic> changes,
  }) async {
    final response = await ref
        .read(apiClientProvider)
        .patch('/knowledge-events/$eventId/members/$contentId', data: changes);
    final event = _detail(response.data);
    _invalidate(eventId, contentId: contentId);
    return event;
  }

  Future<void> removeMember({
    required int eventId,
    required int contentId,
  }) async {
    await ref
        .read(apiClientProvider)
        .delete('/knowledge-events/$eventId/members/$contentId');
    _invalidate(eventId, contentId: contentId);
  }

  KnowledgeEventDetail _detail(Object? data) =>
      KnowledgeEventDetail.fromJson(Map<String, dynamic>.from(data as Map));

  void _invalidate(int eventId, {int? contentId}) {
    ref.invalidate(knowledgeEventDetailProvider(eventId));
    ref.invalidate(knowledgeEventsProvider(null));
    ref.invalidate(activeKnowledgeEventsProvider);
    if (contentId != null) {
      ref.invalidate(knowledgeEventsProvider(contentId));
    }
  }
}
