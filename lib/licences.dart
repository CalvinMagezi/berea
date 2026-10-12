import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licence texts of the native PDFium build shipped inside the app, by file under
/// `licenses/pdfium/` and the component each one covers. Flutter's own notices do not carry
/// these, because the binaries arrive through a build hook and a pod, not as Dart packages.
const pdfiumLicences = {
  'pdfium.txt': 'PDFium',
  'pdfium-binaries.txt': 'PDFium binaries (Benoit Blanchon)',
  'abseil.txt': 'Abseil (in PDFium)',
  'agg23.txt': 'Anti-Grain Geometry (in PDFium)',
  'fast_float.txt': 'fast_float (in PDFium)',
  'freetype.txt': 'FreeType (in PDFium)',
  'icu.txt': 'ICU (in PDFium)',
  'lcms.txt': 'Little CMS (in PDFium)',
  'libjpeg_turbo.txt': 'libjpeg-turbo (in PDFium)',
  'libjpeg_turbo-ijg.txt': 'Independent JPEG Group (in PDFium)',
  'libopenjpeg.txt': 'OpenJPEG (in PDFium)',
  'libpng.txt': 'libpng (in PDFium)',
  'libtiff.txt': 'libtiff (in PDFium)',
  'llvm-libc.txt': 'LLVM libc (in PDFium)',
  'simdutf.txt': 'simdutf (in PDFium)',
  'zlib.txt': 'zlib (in PDFium)',
  'catapult.txt': 'Catapult (in PDFium for Android)',
  'cpu_features.txt': 'cpu_features (in PDFium for Android)',
  'libunwind.txt': 'libunwind (in PDFium for Android)',
};

/// Licence texts for the optional voice, by file under `licenses/voice/`: ONNX Runtime is
/// linked in natively, and the voice pack's model and dictionary arrive as downloads.
const voiceLicences = {
  'onnxruntime-LICENSE.txt': 'ONNX Runtime',
  'onnxruntime-ThirdPartyNotices.txt': 'ONNX Runtime third party notices',
  'apache-2.0.txt': 'Kokoro-82M voice model and voices',
  'cmudict-LICENSE.txt': 'CMU Pronouncing Dictionary',
};

/// Adds the PDFium and voice notices to the licence page Flutter shows.
void registerBundledLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final (folder, texts) in [('pdfium', pdfiumLicences), ('voice', voiceLicences)]) {
      for (final MapEntry(key: file, value: component) in texts.entries) {
        yield LicenseEntryWithLineBreaks([
          component,
        ], await rootBundle.loadString('licenses/$folder/$file'));
      }
    }
  });
}
