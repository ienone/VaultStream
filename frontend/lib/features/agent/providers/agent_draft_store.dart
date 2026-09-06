import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AgentDraftStore {
  static const _keyPrefix = 'agent_draft:';

  String _key(String sessionId) => '$_keyPrefix$sessionId';

  Future<String?> read(String sessionId) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key(sessionId));
  }

  Future<void> write(String sessionId, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(sessionId), value);
  }

  Future<void> remove(String sessionId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(sessionId));
  }
}

final agentDraftStoreProvider = Provider<AgentDraftStore>(
  (ref) => AgentDraftStore(),
);
