import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import 'app_shell.dart';
import 'global_navbar.dart';

/// Marco global Margen: navbar + contenido (+ barra contextual opcional del libro).
class MargenScaffold extends StatelessWidget {
  const MargenScaffold({
    super.key,
    required this.body,
    this.bookContextBar,
    this.showBottomNav = true,
  });

  final Widget body;
  final Widget? bookContextBar;
  final bool showBottomNav;

  @override
  Widget build(BuildContext context) {
    final desktop = useDesktopChrome(context);

    if (desktop) {
      final topBar = (Platform.isIOS || Platform.isAndroid)
          ? const SafeArea(bottom: false, child: GlobalNavbar())
          : const GlobalNavbar();
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF08111F)
            : AppTokens.paper,
        body: DecoratedBox(
          decoration: AppTokens.deskBackground(Theme.of(context).brightness),
          child: Column(
            children: [
              topBar,
              if (bookContextBar != null) bookContextBar!,
              Expanded(
                child: Material(color: Colors.transparent, child: body),
              ),
            ],
          ),
        ),
      );
    }

    // Móvil: cabecera compacta + barra inferior (sin navbar de escritorio).
    final showMobileHeader = bookContextBar == null;
    final mobileBody = DecoratedBox(
      decoration: AppTokens.deskBackground(Theme.of(context).brightness),
      child: Column(
        children: [
          if (showMobileHeader) const MobileShellHeader(),
          if (bookContextBar != null) bookContextBar!,
          Expanded(
            child: SafeArea(top: !showMobileHeader, bottom: false, child: body),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF08111F)
          : AppTokens.paper,
      body: mobileBody,
      bottomNavigationBar: showBottomNav
          ? const SafeArea(top: false, child: GlobalBottomNav())
          : null,
    );
  }
}
