import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class SelectionCropPreview extends StatelessWidget {
  const SelectionCropPreview({
    super.key,
    required this.pixels,
    required this.width,
    required this.height,
    this.maxHeight = 140,
  });

  final Uint8List pixels;
  final int width;
  final int height;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: _decode(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return SizedBox(
            height: maxHeight,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final image = snap.data!;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: FittedBox(
              fit: BoxFit.contain,
              child: RawImage(
                image: image,
                width: width.toDouble(),
                height: height.toDouble(),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<ui.Image?> _decode() async {
    if (width < 1 || height < 1 || pixels.isEmpty) return null;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }
}
