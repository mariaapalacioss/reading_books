import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui/app_snackbar.dart';

/// Mensaje unificado al guardar contenido en Repaso.
const kRepasoSavedSnackMessage = 'Guardado en Repaso';

const kRepasoQuestionsSavedSnackMessage =
    'Se ha guardado el repaso. Puedes verlo en la pestaña Repaso.';

/// Snackbar global + refresco de la biblioteca de repaso.
void notifyRepasoSaved(WidgetRef ref, {String? message}) {
  showAppSnackBar(message ?? kRepasoSavedSnackMessage);
  bumpRepasoReloadTick(ref);
}
