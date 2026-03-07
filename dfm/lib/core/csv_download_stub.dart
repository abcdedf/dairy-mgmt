// lib/core/csv_download_stub.dart
// Mobile implementation: writes CSV to temp directory and opens share sheet.

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void triggerDownload(String fileName, String csvContent) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csvContent);
  await Share.shareXFiles([XFile(file.path)]);
}
