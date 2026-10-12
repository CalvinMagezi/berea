import 'dart:ffi';

import 'package:berea_harness/berea_harness.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_flutter/pdfium_flutter.dart';

/// Page texts of a PDF. Runs off the UI isolate, one at a time, because PDFium is not thread safe.
List<String> pdfPageTexts(
  String path, {
  required int maxPages,
  required int maxChars,
  String? libraryPath,
}) {
  final pdfium = getPdfium(modulePath: libraryPath);
  // Idempotent per process, and never destroyed because a later isolate reads with it.
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
    final pages = <String>[];
    var budget = maxChars;
    for (var i = 0; i < count; i++) {
      pages.add(_pageText(pdfium, doc, i, budget));
      budget -= pages.last.length;
    }
    return pages;
  } finally {
    pdfium.FPDF_CloseDocument(doc);
  }
}

/// Throws the source-too-long error before allocating when the page exceeds [budget].
String _pageText(PDFium pdfium, FPDF_DOCUMENT doc, int index, int budget) {
  final page = pdfium.FPDF_LoadPage(doc, index);
  if (page == nullptr) return '';
  final text = pdfium.FPDFText_LoadPage(page);
  try {
    if (text == nullptr) return '';
    final n = pdfium.FPDFText_CountChars(text);
    if (n <= 0) return '';
    if (n > budget) throw const FormatException(tooLongMessage);
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
