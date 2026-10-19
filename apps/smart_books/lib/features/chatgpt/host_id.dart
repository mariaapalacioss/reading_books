import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _key = 'smartbooks_ext_agent_host_id';

/// ID estable por instalación/host (mismo criterio que `hostId.ts` en la web).
Future<String> getOrCreateExtAgentHostId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_key);
  if (existing != null && existing.isNotEmpty) return existing;
  final id = 'urn:uuid:${const Uuid().v4()}';
  await prefs.setString(_key, id);
  return id;
}
