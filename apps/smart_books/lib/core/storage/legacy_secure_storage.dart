import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Llavero macOS con el nombre de servicio por defecto del plugin (lectura única de migración).
FlutterSecureStorage? legacyMacSecureStorageForMigration() {
  if (!Platform.isMacOS) return null;
  return const FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );
}
