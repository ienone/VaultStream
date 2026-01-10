import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'search_history_provider.g.dart';

@riverpod
class SearchHistory extends _$SearchHistory {
  static const _key = 'search_history';

  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  Future<void> add(String query) async {
    final queryTrimmed = query.trim();
    if (queryTrimmed.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final currentList = state.value ?? [];
    
    // Remove if exists to move to top
    final newList = List<String>.from(currentList)..remove(queryTrimmed);
    newList.insert(0, queryTrimmed);
    
    // Limit to 20 items
    if (newList.length > 20) {
      newList.removeRange(20, newList.length);
    }

    await prefs.setStringList(_key, newList);
    state = AsyncValue.data(newList);
  }

  Future<void> remove(String query) async {
    final prefs = await SharedPreferences.getInstance();
    final currentList = state.value ?? [];
    
    final newList = List<String>.from(currentList)..remove(query);
    
    await prefs.setStringList(_key, newList);
    state = AsyncValue.data(newList);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    state = const AsyncValue.data([]);
  }
}
