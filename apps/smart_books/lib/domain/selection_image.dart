import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Convierte píxeles BGRA (recorte del PDF) a data URL PNG para visión en ChatGPT.
Future<String?> bgraToPngDataUrl(
  Uint8List pixels,
  int width,
  int height,
) async {
  if (width < 1 || height < 1 || pixels.isEmpty) return null;
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888,
    completer.complete,
  );
  final image = await completer.future;
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    final b64 = base64Encode(bytes.buffer.asUint8List());
    return 'data:image/png;base64,$b64';
  } finally {
    image.dispose();
  }
}
