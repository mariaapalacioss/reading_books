import 'package:flutter/material.dart';

import '../../data/models/book.dart';

const languageLabels = {
  'es': 'Español',
  'en': 'Inglés',
  'unknown': 'Sin detectar',
};

String statusLabel(String status) => switch (status) {
  'extracting' => 'Extrayendo texto',
  'needs_ocr' => 'Requiere OCR',
  'ready' => 'Listo para analizar',
  'analyzing' => 'Analizando',
  'partial' => 'Análisis parcial',
  'analyzed' => 'Analizado',
  'error' => 'Revisar libro',
  _ => status,
};

bool statusChipWarn(String status) =>
    status == 'needs_ocr' || status == 'error';

bool statusChipTeal(String status) =>
    status == 'ready' ||
    status == 'analyzed' ||
    status == 'partial' ||
    status == 'analyzing';

Color coverGradientSeed(Book book) {
  final hash = book.id.hashCode.abs();
  return Color(0xFF000000 | (hash & 0xFFFFFF));
}
