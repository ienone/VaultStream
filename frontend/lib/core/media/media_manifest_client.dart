import 'package:dio/dio.dart';

import 'media_asset.dart';

Future<MediaAsset> refreshMediaManifest(
  Dio dio, {
  required int assetId,
  required MediaPurpose purpose,
}) async {
  final response = await dio.get<Map<String, dynamic>>(
    '/media/assets/$assetId/manifest',
    queryParameters: {'purpose': purpose.name},
  );
  final data = response.data;
  if (data == null) {
    throw const FormatException('Media manifest response is empty');
  }
  return MediaAsset.fromJson(data);
}

Future<void> reportLocalMediaFailure(
  Dio dio, {
  required int assetId,
  required int variantId,
  required String errorCode,
}) async {
  await dio.post<void>(
    '/media/assets/$assetId/failures',
    data: {'variant_id': variantId, 'error_code': errorCode},
  );
}
