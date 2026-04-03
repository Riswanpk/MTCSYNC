import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

/// Data class for watermark parameters
class WatermarkParams {
  final String imagePath;
  final String watermarkText;

  WatermarkParams(this.imagePath, this.watermarkText);
}

/// Top-level function for watermarking (can be used with compute)
Future<Uint8List> _processWatermark(WatermarkParams params) async {
  final bytes = await File(params.imagePath).readAsBytes();

  final image = img.decodeImage(bytes);
  if (image == null) return bytes;

  img.drawString(
    image,
    params.watermarkText,
    font: img.arial24,
    x: 16,
    y: 30,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  return Uint8List.fromList(img.encodeJpg(image));
}

/// Adds a watermark (location and time) to the image at [imageFile].
/// Returns a new File with the watermark applied.
/// This function runs the watermarking in a separate isolate to avoid blocking the UI.
Future<File> addWatermark({
  required File imageFile,
  required String watermarkText,
}) async {
  // Run watermarking in a separate isolate using compute
  final watermarkedBytes = await compute(
    _processWatermark,
    WatermarkParams(imageFile.path, watermarkText),
  );

  // Write the watermarked image to the same file (overwrite)
  final watermarkedFile = await imageFile.writeAsBytes(watermarkedBytes, flush: true);

  return watermarkedFile;
}