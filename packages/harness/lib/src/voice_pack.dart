import 'dart:convert';

/// The optional voice pack is published unchanged from its upstream sources on a data-only
/// release, pinned by tag and by hash, so what arrives is byte for byte what was reviewed.
const voicePackRelease = 'voice-1';
const voicePackReleaseUrl =
    'https://github.com/CalvinMagezi/berea/releases/download/$voicePackRelease';
const voicePackFormat = 1;

enum VoiceFileRole { model, voice, lexicon, licence }

/// One published file: where it came from, its size and SHA-256. Licence files travel with the
/// release but the app does not need them on the device.
class VoicePackFile {
  final String name;
  final VoiceFileRole role;
  final String sha256;
  final int bytes;
  final String upstream;
  final String licence;
  const VoicePackFile({
    required this.name,
    required this.role,
    required this.sha256,
    required this.bytes,
    required this.upstream,
    required this.licence,
  });

  bool get onDevice => role != VoiceFileRole.licence;

  Map<String, Object> toJson() => {
    'name': name,
    'role': role.name,
    'sha256': sha256,
    'bytes': bytes,
    'upstream': upstream,
    'licence': licence,
  };

  static VoicePackFile fromJson(Map<String, Object?> j) {
    final sha = j['sha256'];
    final bytes = j['bytes'];
    final name = j['name'];
    if (name is! String || name.isEmpty || name.contains('/') || name.contains('\\')) {
      throw FormatException('Bad file name in the voice manifest: $name');
    }
    if (sha is! String || !_sha256Hex.hasMatch(sha)) {
      throw FormatException('Bad SHA-256 for $name in the voice manifest.');
    }
    if (bytes is! int || bytes <= 0) throw FormatException('Bad size for $name.');
    final role = VoiceFileRole.values.where((r) => r.name == j['role']).firstOrNull;
    if (role == null) throw FormatException('Unknown role for $name.');
    return VoicePackFile(
      name: name,
      role: role,
      sha256: sha,
      bytes: bytes,
      upstream: j['upstream'] as String? ?? '',
      licence: j['licence'] as String? ?? '',
    );
  }
}

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

/// A speaker: the voice file it reads its style from and the name the app shows.
class KokoroSpeaker {
  final String id;
  final String label;
  const KokoroSpeaker(this.id, this.label);
  String get fileName => '$id.bin';
}

const kokoroSpeakers = [
  KokoroSpeaker('af_heart', 'Heart (American, female)'),
  KokoroSpeaker('am_michael', 'Michael (American, male)'),
];

const _kokoroRepo =
    'https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX-timestamped/resolve/'
    'dd4401a9add81ac692d20e240d22ec9dda82cc29';
const _cmudictRepo =
    'https://raw.githubusercontent.com/cmusphinx/cmudict/74790861f652b15e4ac49015a90074ad62a27690';
const kokoroModelFile = 'kokoro-v1.0-timestamped-fp16.onnx';
const cmudictFile = 'cmudict.dict';
const _apache = 'Apache-2.0';
const _cmudictLicence = 'BSD-2-Clause style (Carnegie Mellon University)';

/// Every file of `voice-1`. The model is the half-precision export whose graph also outputs per-token
/// durations, which is what word timings come from.
const voicePackFiles = [
  VoicePackFile(
    name: kokoroModelFile,
    role: VoiceFileRole.model,
    sha256: '220724d5c5e0cc01be30f38faa6cf0c895a7cde6e7773e91db2973c8c7e5123c',
    bytes: 163232776,
    upstream: '$_kokoroRepo/onnx/model_fp16.onnx',
    licence: _apache,
  ),
  VoicePackFile(
    name: 'af_heart.bin',
    role: VoiceFileRole.voice,
    sha256: 'd583ccff3cdca2f7fae535cb998ac07e9fcb90f09737b9a41fa2734ec44a8f0b',
    bytes: 522240,
    upstream: '$_kokoroRepo/voices/af_heart.bin',
    licence: _apache,
  ),
  VoicePackFile(
    name: 'am_michael.bin',
    role: VoiceFileRole.voice,
    sha256: '1d1f21dd8da39c30705cd4c75d039d265e9bc4a2a93ed09bc9e1b1225eb95ba1',
    bytes: 522240,
    upstream: '$_kokoroRepo/voices/am_michael.bin',
    licence: _apache,
  ),
  VoicePackFile(
    name: cmudictFile,
    role: VoiceFileRole.lexicon,
    sha256: '81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22',
    bytes: 3618488,
    upstream: '$_cmudictRepo/cmudict.dict',
    licence: _cmudictLicence,
  ),
  VoicePackFile(
    name: 'LICENSE-CMUdict.txt',
    role: VoiceFileRole.licence,
    sha256: 'bd4ce8e44170a5f9f481310ca85c51de3c4f851a65e679b40e603b143bd3542a',
    bytes: 1754,
    upstream: '$_cmudictRepo/LICENSE',
    licence: _cmudictLicence,
  ),
  VoicePackFile(
    name: 'LICENSE-Apache-2.0.txt',
    role: VoiceFileRole.licence,
    sha256: 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
    bytes: 11358,
    upstream: 'https://www.apache.org/licenses/LICENSE-2.0.txt',
    licence: _apache,
  ),
];

/// The files the app keeps on the device.
Iterable<VoicePackFile> get voicePackDeviceFiles => voicePackFiles.where((f) => f.onDevice);

/// Total download size of the files the app fetches.
int get voicePackDownloadBytes => voicePackDeviceFiles.fold(0, (sum, f) => sum + f.bytes);

String voicePackManifestJson([List<VoicePackFile> files = voicePackFiles]) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': voicePackFormat,
      'release': voicePackRelease,
      'files': [for (final f in files) f.toJson()],
    });

/// Reads a manifest written by `bin/build_voice_pack.dart`, refusing unknown formats and
/// malformed pins.
List<VoicePackFile> parseVoicePackManifest(String json) {
  final root = jsonDecode(json);
  if (root is! Map<String, Object?> || root['format'] != voicePackFormat) {
    throw const FormatException('Not a Berea voice pack manifest.');
  }
  final files = root['files'];
  if (files is! List) throw const FormatException('The voice manifest lists no files.');
  return [for (final f in files) VoicePackFile.fromJson(Map<String, Object?>.from(f as Map))];
}
