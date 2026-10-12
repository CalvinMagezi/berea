import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

/// The text of each page of the PDF at [path], first page first, read with PDFium. Call it off
/// the UI isolate, one document at a time: PDFium is not thread safe. Throws [FormatException]
/// when the file cannot be read as a PDF. [libraryPath] overrides where PDFium is loaded from,
/// for tests; the app finds it bundled.
List<String> pdfPageTexts(String path, {required int maxPages, String? libraryPath}) {
  final pdfium = getPdfium(modulePath: libraryPath);
  // A no-op after the first call in this process; never destroyed, since another isolate may
  // still be reading.
  pdfium.FPDF_InitLibrary();
  final nativePath = path.toNativeUtf8();
  final doc = pdfium.FPDF_LoadDocument(nativePath.cast(), nullptr);
  malloc.free(nativePath);
  if (doc == nullptr) {
    throw FormatException(
      pdfium.FPDF_GetLastError() == FPDF_ERR_PASSWORD
          ? 'This PDF is protected by a password. Remove it and try again.'
          : 'That file could not be read as a PDF.',
    );
  }
  try {
    final count = pdfium.FPDF_GetPageCount(doc);
    if (count > maxPages) {
      throw FormatException('That PDF has $count pages. The limit is $maxPages.');
    }
    return [for (var i = 0; i < count; i++) _pageText(pdfium, doc, i)];
  } finally {
    pdfium.FPDF_CloseDocument(doc);
  }
}

String _pageText(PDFium pdfium, FPDF_DOCUMENT doc, int index) {
  final page = pdfium.FPDF_LoadPage(doc, index);
  if (page == nullptr) return '';
  final text = pdfium.FPDFText_LoadPage(page);
  try {
    if (text == nullptr) return '';
    final n = pdfium.FPDFText_CountChars(text);
    if (n <= 0) return '';
    // Room for every character as a surrogate pair, plus the terminator PDFium writes.
    final capacity = 2 * n + 1;
    final buffer = malloc<UnsignedShort>(capacity);
    try {
      final written = pdfium.FPDFText_GetText(text, 0, n, buffer).clamp(0, capacity);
      final units = buffer.cast<Uint16>().asTypedList(capacity);
      return String.fromCharCodes(units, 0, written > 0 ? written - 1 : 0);
    } finally {
      malloc.free(buffer);
    }
  } finally {
    if (text != nullptr) pdfium.FPDFText_ClosePage(text);
    pdfium.FPDF_ClosePage(page);
  }
}
