import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'plans.dart';
import 'study_store.dart';

/// Encrypted backups the user keeps themselves. AES-256-GCM with a key derived from their
/// passphrase by PBKDF2-HMAC-SHA256. Nothing is sent anywhere; a lost passphrase is unrecoverable.
const backupMagic = 'BEREA-BACKUP-2';

/// Version 2 adds notebooks; version 3 puts notes and study pages in notebooks and scopes
/// conversations. Versions 1 (0.3.0 and earlier) and 2 still restore, and come back merged.
const backupVersion = 3;
const _readableVersions = {1, 2, 3};

/// OWASP's 2023 guidance for PBKDF2-HMAC-SHA256. Stored in the file so it can rise later.
const pbkdf2Iterations = 600000;
const _legacyMagic = 'BEREA-BACKUP-1';
const _legacyIterations = 210000;

/// The header is not authenticated, so a damaged or crafted count could otherwise hang the app.
const maxPbkdf2Iterations = 10000000;
const _saltBytes = 16;
const _iterationBytes = 4;
const _keyBits = 256;

final _cipher = AesGcm.with256bits();

/// Runs off the UI isolate: PBKDF2 in pure Dart takes seconds at this iteration count.
Future<SecretKey> _key(String passphrase, List<int> salt, int iterations) async {
  final bytes = await Isolate.run(() async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _keyBits,
    ).deriveKeyFromPassword(password: passphrase, nonce: salt);
    return key.extractBytes();
  });
  return SecretKey(bytes);
}

/// The running reading plan, carried in a backup so its restored ticks keep their plan.
typedef BackupPlan = ({String id, DateTime start});

/// Layout: magic line, iteration count (4 bytes, big endian), salt, nonce, ciphertext and MAC.
/// The payload is gzipped JSON.
Future<Uint8List> createBackup(
  StudyStore store,
  Map<String, String> importedTranslations,
  String passphrase, {
  BackupPlan? plan,
}) async {
  final tables = store.exportTables();
  final planJson = plan == null
      ? null
      : {'id': plan.id, 'start': plan.start.toUtc().toIso8601String()};
  final created = DateTime.now().toUtc().toIso8601String();
  // Notebooks can make this large; encode off the UI isolate. Locals only cross over.
  final payload = await Isolate.run(
    () => gzip.encode(
      utf8.encode(
        jsonEncode({
          'version': backupVersion,
          'created': created,
          'tables': tables,
          'imports': importedTranslations,
          'plan': ?planJson,
        }),
      ),
    ),
  );
  final salt = SecretKeyData.random(length: _saltBytes).bytes;
  final key = await _key(passphrase, salt, pbkdf2Iterations);
  final box = await _cipher.encrypt(payload, secretKey: key);
  final iterations = ByteData(_iterationBytes)..setUint32(0, pbkdf2Iterations);
  return Uint8List.fromList([
    ...utf8.encode('$backupMagic\n'),
    ...iterations.buffer.asUint8List(),
    ...salt,
    ...box.concatenation(),
  ]);
}

class BackupContents {
  final int version;
  final Map<String, List<Map<String, Object?>>> tables;
  final Map<String, String> imports;

  /// Null for a backup made with no plan running, or before backups carried one.
  final BackupPlan? plan;
  const BackupContents(this.version, this.tables, this.imports, {this.plan});

  /// Older backups have no notebook tables, so restoring one keeps the notebooks on the device.
  bool get hasNotebooks => tables.containsKey('notebooks');
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
  final current = utf8.encode('$backupMagic\n');
  final legacy = utf8.encode('$_legacyMagic\n');
  final int headerLength, iterations;
  if (_startsWith(bytes, current) && bytes.length >= current.length + _iterationBytes) {
    headerLength = current.length + _iterationBytes;
    iterations = ByteData.sublistView(bytes, current.length, headerLength).getUint32(0);
  } else if (_startsWith(bytes, legacy)) {
    headerLength = legacy.length;
    iterations = _legacyIterations;
  } else {
    throw const BackupException('This is not a Berea backup file.');
  }
  final minimum = headerLength + _saltBytes + _cipher.nonceLength + _cipher.macAlgorithm.macLength;
  if (bytes.length < minimum ||
      iterations < _legacyIterations ||
      iterations > maxPbkdf2Iterations) {
    throw const BackupException('The backup file is damaged.');
  }
  final salt = bytes.sublist(headerLength, headerLength + _saltBytes);
  final box = SecretBox.fromConcatenation(
    bytes.sublist(headerLength + _saltBytes),
    nonceLength: _cipher.nonceLength,
    macLength: _cipher.macAlgorithm.macLength,
  );
  final List<int> clear;
  try {
    clear = await _cipher.decrypt(box, secretKey: await _key(passphrase, salt, iterations));
  } on SecretBoxAuthenticationError {
    throw const BackupException('Wrong passphrase, or the file is damaged.');
  }
  try {
    final json = await Isolate.run(
      () => jsonDecode(utf8.decode(gzip.decode(clear))),
    ) as Map<String, dynamic>;
    final version = json['version'];
    if (version is! int || !_readableVersions.contains(version)) {
      throw BackupException('Backup version $version is not supported.');
    }
    final tables = (json['tables'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, [for (final r in v as List) Map<String, Object?>.from(r as Map)]),
    );
    for (final t in tables.keys) {
      if (!StudyStore.userTables.contains(t)) throw BackupException('Unknown table $t in backup.');
    }
    return BackupContents(
      version,
      tables,
      Map<String, String>.from(json['imports'] as Map? ?? const {}),
      plan: _plan(json['plan']),
    );
  } on BackupException {
    rethrow;
  } catch (_) {
    throw const BackupException('The backup file is damaged.');
  }
}

/// A plan this version no longer offers, or a damaged entry, restores as no plan: the ticks
/// still come back and nothing else depends on it.
BackupPlan? _plan(Object? json) {
  if (json is! Map) return null;
  final (id, start) = (json['id'], json['start']);
  if (id is! String || start is! String || planById(id) == null) return null;
  final when = DateTime.tryParse(start);
  return when == null ? null : (id: id, start: when.toLocal());
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
