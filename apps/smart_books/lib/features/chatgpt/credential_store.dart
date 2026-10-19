import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/storage/legacy_secure_storage.dart';
import '../../core/storage/secure_storage_factory.dart';
import 'chatgpt_credentials.dart';

/// Credenciales pendientes antes de iniciar sesión en Supabase (misma app, otro paso).
const kChatGptPendingUserId = '__pending_pre_supabase__';

class ChatGptCredentialStore {
  ChatGptCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? createAppSecureStorage();

  final FlutterSecureStorage _storage;

  final Map<String, ChatGptCredentials?> _memory = {};
  ChatGptCredentials? _pendingMemory;
  var _pendingLoaded = false;

  String _key(String userId) => 'chatgpt_credentials_$userId';

  static const _pendingKey = 'chatgpt_credentials_pending';

  Future<ChatGptCredentials?> load(String smartbooksUserId) async {
    if (_memory.containsKey(smartbooksUserId)) {
      return _memory[smartbooksUserId];
    }
    var raw = await _storage.read(key: _key(smartbooksUserId));
    var migrated = false;
    if (raw == null || raw.isEmpty) {
      raw = await _readLegacy(_key(smartbooksUserId));
      migrated = raw != null && raw.isNotEmpty;
    }
    if (raw == null || raw.isEmpty) {
      _memory[smartbooksUserId] = null;
      return null;
    }
    final creds = ChatGptCredentials.decode(raw);
    if (creds.smartbooksUserId != smartbooksUserId) {
      _memory[smartbooksUserId] = null;
      return null;
    }
    _memory[smartbooksUserId] = creds;
    if (migrated) {
      await _write(_key(smartbooksUserId), creds.encode());
    }
    return creds;
  }

  Future<ChatGptCredentials?> loadPending() async {
    if (_pendingLoaded) return _pendingMemory;
    var raw = await _storage.read(key: _pendingKey);
    var migrated = false;
    if (raw == null || raw.isEmpty) {
      raw = await _readLegacy(_pendingKey);
      migrated = raw != null && raw.isNotEmpty;
    }
    _pendingLoaded = true;
    if (raw == null || raw.isEmpty) {
      _pendingMemory = null;
      return null;
    }
    _pendingMemory = ChatGptCredentials.decode(raw);
    if (migrated) {
      await _write(_pendingKey, _pendingMemory!.encode());
    }
    return _pendingMemory;
  }

  Future<String?> _readLegacy(String storageKey) async {
    final legacy = legacyMacSecureStorageForMigration();
    if (legacy == null) return null;
    final raw = await legacy.read(key: storageKey);
    if (raw == null || raw.isEmpty) return null;
    await legacy.delete(key: storageKey);
    return raw;
  }

  Future<void> save(ChatGptCredentials credentials) async {
    await _write(_key(credentials.smartbooksUserId), credentials.encode());
    _memory[credentials.smartbooksUserId] = credentials;
  }

  Future<void> savePending(ChatGptCredentials credentials) async {
    final pending = ChatGptCredentials(
      email: credentials.email,
      subject: credentials.subject,
      clientId: credentials.clientId,
      extAgentHostId: credentials.extAgentHostId,
      idToken: credentials.idToken,
      accessToken: credentials.accessToken,
      refreshToken: credentials.refreshToken,
      tokenType: credentials.tokenType,
      expiresAt: credentials.expiresAt,
      scopes: credentials.scopes,
      smartbooksUserId: kChatGptPendingUserId,
      savedAt: credentials.savedAt,
    );
    await _write(_pendingKey, pending.encode());
    _pendingMemory = pending;
    _pendingLoaded = true;
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      if (e.code == '-34018' || (e.message ?? '').contains('-34018')) {
        throw Exception(
          'No se pudo guardar en el llavero de macOS (permiso Keychain). '
          'Reconstruye la app tras actualizar entitlements o contacta soporte si persiste.',
        );
      }
      rethrow;
    }
  }

  /// Tras login Supabase, mueve credenciales pendientes al usuario real.
  Future<bool> adoptPendingForUser(String smartbooksUserId) async {
    final pending = await loadPending();
    if (pending == null) return false;
    final linked = ChatGptCredentials(
      email: pending.email,
      subject: pending.subject,
      clientId: pending.clientId,
      extAgentHostId: pending.extAgentHostId,
      idToken: pending.idToken,
      accessToken: pending.accessToken,
      refreshToken: pending.refreshToken,
      tokenType: pending.tokenType,
      expiresAt: pending.expiresAt,
      scopes: pending.scopes,
      smartbooksUserId: smartbooksUserId,
      savedAt: pending.savedAt,
    );
    await save(linked);
    await clearPending();
    return true;
  }

  Future<void> clear(String smartbooksUserId) async {
    await _storage.delete(key: _key(smartbooksUserId));
    _memory[smartbooksUserId] = null;
  }

  Future<void> clearPending() async {
    await _storage.delete(key: _pendingKey);
    _pendingMemory = null;
    _pendingLoaded = true;
  }

  /// Tras migrar opciones de Keychain o depuración; la siguiente lectura vuelve al llavero.
  void clearMemoryCache() {
    _memory.clear();
    _pendingMemory = null;
    _pendingLoaded = false;
  }
}
