import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/media/media_asset.dart';
import '../../../core/media/media_manifest_client.dart';
import '../../../core/media/media_source_session.dart';
import '../../../core/network/api_client.dart';

class DocumentPdfReadException implements Exception {
  const DocumentPdfReadException(this.message);

  final String message;
}

final documentPdfProvider = FutureProvider.autoDispose.family<Uint8List, int>((
  ref,
  assetId,
) async {
  final dio = ref.watch(apiClientProvider);
  final client = http.Client();
  ref.onDispose(client.close);
  const limit = 64 * 1024 * 1024;
  try {
    final asset = await refreshMediaManifest(
      dio,
      assetId: assetId,
      purpose: MediaPurpose.detail,
    );
    if (!ref.mounted) throw StateError('Document preview was closed');
    final session = MediaSourceSession.fromAsset(asset);
    var refreshed = false;
    do {
      refreshed = false;
      final source = session.current;
      if (source == null) break;
      if (!source.clientFetchAllowed || source.mimeType != 'application/pdf') {
        continue;
      }
      try {
        // Signed resource requests must never inherit the control-plane token.
        final bytes = await (() async {
          final response = await client.send(
            http.Request('GET', Uri.parse(source.url)),
          );
          if (response.statusCode == 401 || response.statusCode == 403) {
            throw const DocumentPdfReadException('文件访问未获授权');
          }
          if (response.statusCode == 410 &&
              source.sourceKind == MediaSourceKind.localSigned &&
              !session.automaticRefreshAttempted) {
            await response.stream.drain<void>();
            session.markAutomaticRefreshAttempted();
            final updated = await refreshMediaManifest(
              dio,
              assetId: assetId,
              purpose: MediaPurpose.detail,
            );
            if (!ref.mounted) throw StateError('Document preview was closed');
            session.replaceManifest(updated);
            refreshed = true;
            return null;
          }
          if (response.statusCode == 404 &&
              source.sourceKind == MediaSourceKind.localSigned &&
              source.variantId != null) {
            await reportLocalMediaFailure(
              dio,
              assetId: assetId,
              variantId: source.variantId!,
              errorCode: 'media_blob_missing',
            ).catchError((Object _) {});
          }
          if (response.statusCode != 200) {
            await response.stream.drain<void>();
            return null;
          }
          if ((response.contentLength ?? 0) > limit) {
            throw const DocumentPdfReadException('文件超过 64 MiB，请打开原文件阅读');
          }
          final buffer = BytesBuilder(copy: false);
          await for (final chunk in response.stream) {
            if (buffer.length + chunk.length > limit) {
              throw const DocumentPdfReadException('文件超过 64 MiB，请打开原文件阅读');
            }
            buffer.add(chunk);
          }
          final data = buffer.takeBytes();
          if (data.length < 5 ||
              String.fromCharCodes(data.take(5)) != '%PDF-') {
            throw const DocumentPdfReadException('文件不是可读取的 PDF');
          }
          return data;
        })().timeout(const Duration(seconds: 60));
        if (bytes != null) return bytes;
      } on http.ClientException {
        // Continue through the server-provided candidates in order.
      } on TimeoutException {
        throw const DocumentPdfReadException('原文件读取超时，请重试');
      }
    } while (refreshed || session.moveNext());
    throw const DocumentPdfReadException('原文件暂时不可用，请重试');
  } finally {
    client.close();
  }
}, retry: (_, _) => null);
