import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'study_store.dart';

/// Encrypted backups the user keeps themselves. AES-256-GCM with a key derived from their
/// passphrase by PBKDF2-HMAC-SHA256. Nothing is sent anywhere; a lost passphrase is unrecoverable.
const backupMagic = 'BEREA-BACKUP-1';
const backupVersion = 1;
const pbkdf2Iterations = 210000;
const _saltBytes = 16;
const _keyBits = 256;

final _cipher = AesGcm.with256bits();

Future<SecretKey> _key(String passphrase, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: pbkdf2Iterations,
  bits: _keyBits,
).deriveKeyFromPassword(password: passphrase, nonce: salt);

/// Layout: magic line, then salt, nonce, ciphertext and MAC. The payload is gzipped JSON.
Future<Uint8List> createBackup(
  StudyStore store,
  Map<String, String> importedTranslations,
  String passphrase,
) async {
  final payload = gzip.encode(
    utf8.encode(
      jsonEncode({
        'version': backupVersion,
        'created': DateTime.now().toUtc().toIso8601String(),
        'tables': store.exportTables(),
        'imports': importedTranslations,
      }),
    ),
  );
  final salt = SecretKeyData.random(length: _saltBytes).bytes;
  final box = await _cipher.encrypt(payload, secretKey: await _key(passphrase, salt));
  return Uint8List.fromList([...utf8.encode('$backupMagic\n'), ...salt, ...box.concatenation()]);
}

class BackupContents {
  final Map<String, List<Map<String, Object?>>> tables;
  final Map<String, String> imports;
  const BackupContents(this.tables, this.imports);
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// Decrypts and checks a backup. Throws [BackupException] on a wrong passphrase or a damaged
/// file; callers change nothing until this returns.
Future<BackupContents> readBackup(Uint8List bytes, String passphrase) async {
  final header = utf8.encode('$backupMagic\n');
  if (bytes.length < header.length + _saltBytes ||
      utf8.decode(bytes.sublist(0, header.length), allowMalformed: true) != '$backupMagic\n') {
    throw const BackupException('This is not a Berea backup file.');
  }
  final salt = bytes.sublist(header.length, header.length + _saltBytes);
  final box = SecretBox.fromConcatenation(
    bytes.sublist(header.length + _saltBytes),
    nonceLength: _cipher.nonceLength,
    macLength: _cipher.macAlgorithm.macLength,
  );
  final List<int> clear;
  try {
    clear = await _cipher.decrypt(box, secretKey: await _key(passphrase, salt));
  } on SecretBoxAuthenticationError {
    throw const BackupException('Wrong passphrase, or the file is damaged.');
  }
  final json = jsonDecode(utf8.decode(gzip.decode(clear))) as Map<String, dynamic>;
  if (json['version'] != backupVersion) {
    throw BackupException('Backup version ${json['version']} is not supported.');
  }
  final tables = (json['tables'] as Map<String, dynamic>).map(
    (k, v) => MapEntry(k, [for (final r in v as List) Map<String, Object?>.from(r as Map)]),
  );
  for (final t in tables.keys) {
    if (!StudyStore.userTables.contains(t)) throw BackupException('Unknown table $t in backup.');
  }
  return BackupContents(tables, Map<String, String>.from(json['imports'] as Map? ?? const {}));
}
