import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Lee bytes completos del archivo elegido (incl. iCloud/Archivos en iOS).
Future<Uint8List?> readPlatformFileBytes(PlatformFile file) async {
  final inline = file.bytes;
  if (inline != null && inline.isNotEmpty) {
    return inline;
  }

  final path = file.path;
  if (path == null || path.isEmpty) return null;

  final ioFile = File(path);
  if (!await ioFile.exists()) return null;

  final length = await ioFile.length();
  if (length <= 0) return null;

  return ioFile.readAsBytes();
}

bool looksLikePdf(Uint8List bytes) {
  if (bytes.length < 5) return false;
  return bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}
