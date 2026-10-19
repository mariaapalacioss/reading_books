import 'dart:io';

import 'package:flutter/material.dart';

import 'margen_scaffold.dart';

/// Teléfonos usan shell móvil aunque estén en horizontal (evita navbar de escritorio bajo el notch).
bool useDesktopChrome(BuildContext context) {
  if (Platform.isMacOS) return true;
  final size = MediaQuery.sizeOf(context);
  if (Platform.isIOS || Platform.isAndroid) {
    if (size.shortestSide < 600) return false;
  }
  return size.width >= 900;
}

bool useWideLayout(BuildContext context) => useDesktopChrome(context);

/// Shell de rutas internas (Biblioteca, Buscar, Repaso, Ajustes).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MargenScaffold(body: child);
  }
}
