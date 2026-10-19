import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Almacenamiento seguro por plataforma (ChatGPT credentials, etc.).
///
/// macOS: el Keychain con «data protection» exige `keychain-access-groups` y perfil
/// de aprovisionamiento; sin ello aparece errSecMissingEntitlement (-34018).
/// Nombre estable del servicio Keychain (kSecAttrService) para Smart Books.
const kSmartBooksKeychainService = 'com.bookifi.smart_books.credentials';

/// Usamos el keychain legacy documentado por flutter_secure_storage para apps sandbox.
FlutterSecureStorage createAppSecureStorage() {
  if (Platform.isMacOS) {
    return const FlutterSecureStorage(
      mOptions: MacOsOptions(
        accountName: kSmartBooksKeychainService,
        accessibility: KeychainAccessibility.first_unlock_this_device,
        useDataProtectionKeyChain: false,
      ),
    );
  }
  if (Platform.isIOS) {
    return const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
  }
  return const FlutterSecureStorage();
}
