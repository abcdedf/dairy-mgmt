// lib/core/csv_download_web.dart
// Web implementation: triggers browser file download via Blob + anchor click.

import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

void triggerDownload(String fileName, String csvContent) {
  final bytes = utf8.encode(csvContent);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);
}
