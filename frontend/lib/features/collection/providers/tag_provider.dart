import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/network/api_client.dart';

part 'tag_provider.g.dart';

class TagInfo {
  final String name;
  final int count;

  TagInfo({required this.name, required this.count});

  factory TagInfo.fromJson(Map<String, dynamic> json) {
    return TagInfo(
      name: json['name'] as String,
      count: json['count'] as int,
    );
  }
}

@riverpod
Future<List<TagInfo>> allTags(Ref ref) async {
  final dio = ref.watch(apiClientProvider);
  final response = await dio.get('/tags');
  final List<dynamic> data = response.data;
  return data.map((e) => TagInfo.fromJson(e as Map<String, dynamic>)).toList();
}
