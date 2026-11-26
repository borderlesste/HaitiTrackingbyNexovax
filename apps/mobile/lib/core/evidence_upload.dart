import 'dart:io';

enum EvidenceType {
  jpeg('jpg', 'image/jpeg', [0xff, 0xd8, 0xff]),
  png('png', 'image/png', [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  pdf('pdf', 'application/pdf', [0x25, 0x50, 0x44, 0x46, 0x2d]);

  const EvidenceType(this.extension, this.mimeType, this._signature);

  final String extension;
  final String mimeType;
  final List<int> _signature;
}

class InvalidEvidence extends FormatException {
  const InvalidEvidence(super.message);
}

Future<EvidenceType> inspectEvidence(File file, {bool allowPdf = false}) async {
  final input = await file.open();
  try {
    final length = await input.length();
    if (length == 0 || length > 10 * 1024 * 1024) {
      throw const InvalidEvidence(
          'El archivo debe tener contenido y pesar como máximo 10 MiB.');
    }
    final header = await input.read(8);
    for (final type in EvidenceType.values) {
      final signature = type._signature;
      if ((allowPdf || type != EvidenceType.pdf) &&
          header.length >= signature.length &&
          signature.indexed.every((byte) => header[byte.$1] == byte.$2)) {
        return type;
      }
    }
    throw InvalidEvidence(allowPdf
        ? 'Elige un archivo JPEG, PNG o PDF.'
        : 'Elige una imagen JPEG o PNG.');
  } finally {
    await input.close();
  }
}
