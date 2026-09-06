import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../models/render_config_preset.dart';

final renderConfigPresetsProvider =
    FutureProvider.autoDispose<List<RenderConfigPreset>>((ref) async {
      final response = await ref
          .watch(apiClientProvider)
          .get('/render-config-presets');
      return (response.data as List)
          .map(
            (item) => RenderConfigPreset.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    });
