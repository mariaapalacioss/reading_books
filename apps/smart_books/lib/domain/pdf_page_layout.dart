import 'dart:math' as math;
import 'dart:ui';

import 'rects.dart';

/// Rectángulo donde el PDF se dibuja dentro del área del lector (letterbox incluido).
class ReaderPdfLayout {
  const ReaderPdfLayout({required this.offset, required this.size});

  final Offset offset;
  final Size size;

  bool contains(Offset local) {
    return local.dx >= offset.dx &&
        local.dy >= offset.dy &&
        local.dx <= offset.dx + size.width &&
        local.dy <= offset.dy + size.height;
  }

  /// Coordenadas normalizadas 0–1 respecto a la página PDF.
  Offset toNormalized(Offset local) {
    if (size.width <= 0 || size.height <= 0) return Offset.zero;
    final nx = ((local.dx - offset.dx) / size.width).clamp(0.0, 1.0);
    final ny = ((local.dy - offset.dy) / size.height).clamp(0.0, 1.0);
    return Offset(nx, ny);
  }

  Rect normRectToLocal(NormRect r) {
    return Rect.fromLTWH(
      offset.dx + r.x * size.width,
      offset.dy + r.y * size.height,
      r.w * size.width,
      r.h * size.height,
    );
  }

  /// Punto en espacio de escena (mismo sistema que [toNormalized] / overlays).
  Offset fromNormalized(double nx, double ny) {
    return Offset(
      offset.dx + nx.clamp(0.0, 1.0) * size.width,
      offset.dy + ny.clamp(0.0, 1.0) * size.height,
    );
  }
}

ReaderPdfLayout layoutPdfPageInBox({
  required double boxWidth,
  required double boxHeight,
  required double pageWidth,
  required double pageHeight,
}) {
  if (boxWidth <= 0 || boxHeight <= 0 || pageWidth <= 0 || pageHeight <= 0) {
    return ReaderPdfLayout(
      offset: Offset.zero,
      size: Size(boxWidth, boxHeight),
    );
  }
  final scale = math.min(boxWidth / pageWidth, boxHeight / pageHeight);
  final w = pageWidth * scale;
  final h = pageHeight * scale;
  return ReaderPdfLayout(
    offset: Offset((boxWidth - w) / 2, (boxHeight - h) / 2),
    size: Size(w, h),
  );
}
