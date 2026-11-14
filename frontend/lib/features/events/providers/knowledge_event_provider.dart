import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/sse_service.dart';
import '../models/knowledge_event.dart';

typedef EventPageQuery = ({int page, String title, int? contentId});

final knowledgeEventsProvider = FutureProvider.autoDispose
    .family<KnowledgeEventListResponse, EventPageQuery>((ref, query) async {
      refreshOnEvents(
        ref,
        (event) => event.type.startsWith('knowledge_event_'),
      );
      final response = await ref
          .watch(apiClientProvider)
          .get(
            '/knowledge-events',
            queryParameters: {
              'page': query.page,
              'size': 20,
              'content_id': ?query.contentId,
              if (query.contentId == null) 'status': 'active',
              if (query.title.isNotEmpty) 'q': query.title,
            },
          );
      return KnowledgeEventListResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final knowledgeEventDetailProvider = FutureProvider.autoDispose
    .family<KnowledgeEventDetail, int>((ref, eventId) async {
      refreshOnEvents(
        ref,
        (event) =>
            event.type.startsWith('knowledge_event_') &&
            event.data['id'] == eventId,
      );
      final response = await ref
          .watch(apiClientProvider)
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
    _invalidate(event.id);
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
            'note': ?note,
          },
        );
    final event = _detail(response.data);
    _invalidate(eventId);
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
    _invalidate(eventId);
    return event;
  }

  Future<void> removeMember({
    required int eventId,
    required int contentId,
  }) async {
    await ref
        .read(apiClientProvider)
        .delete('/knowledge-events/$eventId/members/$contentId');
    _invalidate(eventId);
  }

  KnowledgeEventDetail _detail(Object? data) =>
      KnowledgeEventDetail.fromJson(Map<String, dynamic>.from(data as Map));

  void _invalidate(int eventId) {
    ref.invalidate(knowledgeEventDetailProvider(eventId));
    ref.invalidate(knowledgeEventsProvider);
  }
}
