import 'dart:io';
import 'package:image_watermark/image_watermark.dart';
import 'package:flutter/material.dart';

/// Adds a watermark (location and time) to the image at [imageFile].
/// Returns a new File with the watermark applied.
Future<File> addWatermark({
  required File imageFile,
  required String watermarkText,
}) async {
  // Read image from file
  final bytes = await imageFile.readAsBytes();

  // Add watermark using image_watermark
  final watermarkedBytes = await ImageWatermark.addTextWatermark(
    imgBytes: bytes,
    watermarkText: watermarkText,
    color: Colors.white,
    dstX: 16,
    dstY: 30,
  );

  // Write the watermarked image to the same file (overwrite)
  final watermarkedFile = await imageFile.writeAsBytes(watermarkedBytes, flush: true);

  return watermarkedFile;
}