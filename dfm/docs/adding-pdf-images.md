# Adding or Updating PDF Images

## Background

Flutter web has known issues with `rootBundle.load()` and `networkImage()` failing to load asset images in debug mode (Flutter issues [#158768](https://github.com/flutter/flutter/issues/158768), [#137523](https://github.com/flutter/flutter/issues/137523), [#128230](https://github.com/flutter/flutter/issues/128230)).

**Workaround:** PNG images are base64-encoded and embedded as Dart constants in `lib/core/pdf_images.dart`. The PDF generator (`lib/core/document_pdf.dart`) uses `pw.MemoryImage(bytes)` to render them.

## Current Images

| Constant | Source File | Used In |
|----------|------------|---------|
| `challanHeaderBytes` | `assets/images/challan_header.png` | Challan PDF header |
| `challanFooterBytes` | `assets/images/challan_footer.png` | Challan PDF footer |
| `invoiceHeaderBytes` | `assets/images/invoice_header.png` | Invoice PDF header |
| `invoiceFooterBytes` | `assets/images/invoice_footer.png` | Invoice PDF footer |

## Procedure to Add or Replace an Image

### Step 1: Place the PNG file

Put the new PNG file in `dfm/assets/images/`. Use descriptive names like `<document>_<position>.png`.

```
dfm/assets/images/my_new_image.png
```

### Step 2: Generate the base64 constant

Run from the project root:

```bash
base64 -i dfm/assets/images/my_new_image.png | tr -d '\n'
```

### Step 3: Update `lib/core/pdf_images.dart`

Add (or replace) the base64 string constant and its getter:

```dart
const _myNewImageB64 = '<paste base64 string here>';

Uint8List get myNewImageBytes => base64Decode(_myNewImageB64);
```

### Step 4: Use in `document_pdf.dart`

```dart
import 'pdf_images.dart';

// In the PDF build method:
final img = pw.MemoryImage(myNewImageBytes);
pw.Image(img, width: ctx.page.pageFormat.availableWidth);
```

### Step 5: Test

Run `flutter run -d chrome` and verify the image appears in the PDF.

## Regenerating All Images at Once

If you need to regenerate the entire `pdf_images.dart` file (e.g. after replacing multiple PNGs), run this from the repo root:

```bash
cat > dfm/lib/core/pdf_images.dart << 'HEADER'
// Auto-generated — do not edit manually
import 'dart:convert';
import 'dart:typed_data';

HEADER

for img in challan_header challan_footer invoice_header invoice_footer; do
  var=$(echo $img | sed 's/_\(.\)/\U\1/g')  # camelCase
  echo -n "const _${var}B64 = '" >> dfm/lib/core/pdf_images.dart
  base64 -i "dfm/assets/images/${img}.png" | tr -d '\n' >> dfm/lib/core/pdf_images.dart
  echo "';" >> dfm/lib/core/pdf_images.dart
  echo "" >> dfm/lib/core/pdf_images.dart
done

cat >> dfm/lib/core/pdf_images.dart << 'FOOTER'
Uint8List get challanHeaderBytes => base64Decode(_challanHeaderB64);
Uint8List get challanFooterBytes => base64Decode(_challanFooterB64);
Uint8List get invoiceHeaderBytes => base64Decode(_invoiceHeaderB64);
Uint8List get invoiceFooterBytes => base64Decode(_invoiceFooterB64);
FOOTER
```

## Notes

- Keep source PNGs in `assets/images/` for reference, even though they're not loaded at runtime.
- The `pubspec.yaml` asset declarations are optional (they're not used by the code) but can be kept for documentation.
- Recommended image width: 1920px (matches A4 at 150+ DPI). Keep file sizes reasonable (under 200KB each).
- The base64 encoding adds ~33% to the file size. Four images totaling ~460KB of PNGs become ~610KB of base64 in the Dart source. This is compiled into the JS bundle.
