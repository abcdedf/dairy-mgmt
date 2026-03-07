// lib/core/csv_export.dart
//
// Client-side CSV generation and download.
// Web: Blob + anchor click.  Mobile: temp file + share sheet.

// Conditional import: web gets browser download, mobile gets share_plus.
import 'csv_download_stub.dart'
    if (dart.library.js_interop) 'csv_download_web.dart' as download;

/// Generates a CSV string from headers and rows, then triggers a download.
void exportCsv({
  required String fileName,
  required List<String> headers,
  required List<List<String>> rows,
}) {
  final buf = StringBuffer();
  buf.writeln(headers.map(_escape).join(','));
  for (final row in rows) {
    buf.writeln(row.map(_escape).join(','));
  }
  download.triggerDownload(fileName, buf.toString());
}

/// Escapes a CSV field: wraps in quotes if it contains comma, quote, or newline.
String _escape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
