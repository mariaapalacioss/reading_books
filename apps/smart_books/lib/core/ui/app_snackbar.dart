import 'package:flutter/material.dart';

import '../../app/router.dart';

/// Muestra un SnackBar aunque no haya [Scaffold] ancestro (p. ej. layout escritorio Margen).
void showAppSnackBar(
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger != null) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: duration),
    );
    return;
  }
  debugPrint('[snackbar] $message');
}

int _loadingOverlayDepth = 0;

/// Muestra overlay de carga sin bloquear el caller ([showDialog] no debe awaitarse).
void showAppLoadingOverlay() {
  final rootCtx = rootNavigatorKey.currentContext;
  if (rootCtx == null) {
    debugPrint('[REPASO FLOW] loading skipped: no root navigator context');
    return;
  }
  if (_loadingOverlayDepth > 0) {
    debugPrint(
      '[REPASO FLOW] loading already visible (depth=$_loadingOverlayDepth)',
    );
    _loadingOverlayDepth++;
    return;
  }
  _loadingOverlayDepth = 1;
  debugPrint('[REPASO FLOW] showing loading');
  showDialog<void>(
    context: rootCtx,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  ).whenComplete(() {
    _loadingOverlayDepth = 0;
    debugPrint('[REPASO FLOW] loading route closed');
  });
}

void dismissAppLoadingOverlay() {
  debugPrint('[REPASO FLOW] dismiss loading (depth=$_loadingOverlayDepth)');
  if (_loadingOverlayDepth <= 0) return;
  final rootCtx = rootNavigatorKey.currentContext;
  if (rootCtx == null) {
    _loadingOverlayDepth = 0;
    return;
  }
  final nav = Navigator.of(rootCtx, rootNavigator: true);
  if (nav.canPop()) {
    nav.pop();
  }
  _loadingOverlayDepth = 0;
}

@Deprecated('Use showAppLoadingOverlay() without await')
Future<T?> showAppLoadingDialog<T>() async {
  showAppLoadingOverlay();
  return null;
}
