import 'dart:typed_data';

/// Gemma reads 16 kHz mono 16-bit PCM WAV.
const voiceSampleRate = 16000;
const voiceChannels = 1;
const voiceBitsPerSample = 16;
const voiceBytesPerSecond = voiceSampleRate * voiceChannels * voiceBitsPerSample ~/ 8;

/// A tenth of a second; anything shorter is a header with no speech in it.
const minVoiceWavDataBytes = voiceBytesPerSecond ~/ 10;

/// The recorder can run a little past the cap before it stops.
const voiceStopSlack = Duration(seconds: 2);

const _wavPcmFormat = 1;
const _wavExtensibleFormat = 0xFFFE;
const _unsetSize = 0xFFFFFFFF;
const _idBytes = 4;
const _riffSizeOffset = 4;
const _waveIdOffset = 8;
const _firstChunkOffset = 12;
const _chunkHeaderBytes = 8;
const _riffHeaderBytes = 8;
const _fmtMinBytes = 16;
const _fmtChannelsOffset = 2;
const _fmtRateOffset = 4;
const _fmtBitsOffset = 14;
const _fmtExtensibleBytes = 40;
const _fmtSubformatOffset = 24;

enum WavProblem {
  notWav,
  noFormat,
  notPcm,
  wrongChannels,
  wrongRate,
  wrongBits,
  noData,
  sizeMismatch,
  tooShort,
  tooLong,
}

class _Layout {
  int? fmtAt;
  int fmtSize = 0;
  int? dataAt;
  int dataSize = 0;
}

_Layout? _layout(Uint8List wav) {
  if (wav.length < _firstChunkOffset ||
      String.fromCharCodes(wav, 0, _idBytes) != 'RIFF' ||
      String.fromCharCodes(wav, _waveIdOffset, _waveIdOffset + _idBytes) != 'WAVE') {
    return null;
  }
  final view = ByteData.sublistView(wav);
  final out = _Layout();
  var offset = _firstChunkOffset;
  while (offset + _chunkHeaderBytes <= wav.length && out.dataAt == null) {
    final id = String.fromCharCodes(wav, offset, offset + _idBytes);
    final size = view.getUint32(offset + _idBytes, Endian.little);
    final body = offset + _chunkHeaderBytes;
    if (id == 'fmt ') {
      out
        ..fmtAt = body
        ..fmtSize = size;
    } else if (id == 'data') {
      out
        ..dataAt = body
        ..dataSize = size;
    }
    offset = body + size + size % 2;
  }
  return out;
}

int _riffSize(Uint8List wav) => ByteData.sublistView(wav).getUint32(_riffSizeOffset, Endian.little);

/// The sizes in the header match the file, as they do once the recorder has finished writing.
bool wavSizesConsistent(Uint8List wav) {
  final l = _layout(wav);
  if (l == null || l.dataAt == null || l.dataSize == 0) return false;
  return _riffSize(wav) + _riffHeaderBytes == wav.length && l.dataAt! + l.dataSize <= wav.length;
}

/// Fixes the sizes a streaming writer leaves unset, when the data chunk runs to the end.
Uint8List repairWavSizes(Uint8List wav) {
  final l = _layout(wav);
  if (l == null || l.dataAt == null) return wav;
  final available = wav.length - l.dataAt!;
  final unset = l.dataSize == 0 || l.dataSize == _unsetSize || l.dataSize > available;
  if (!unset && _riffSize(wav) + _riffHeaderBytes == wav.length) return wav;
  final fixed = Uint8List.fromList(wav);
  final view = ByteData.sublistView(fixed);
  view.setUint32(_riffSizeOffset, wav.length - _riffHeaderBytes, Endian.little);
  if (unset) view.setUint32(l.dataAt! - _idBytes, available, Endian.little);
  return fixed;
}

/// Sample rate from the format chunk, or null if there is none.
int? wavSampleRate(Uint8List wav) {
  final at = _layout(wav)?.fmtAt;
  if (at == null || at + _fmtMinBytes > wav.length) return null;
  return ByteData.sublistView(wav).getUint32(at + _fmtRateOffset, Endian.little);
}

/// Null when [wav] is 16 kHz mono 16-bit PCM of a usable length, otherwise what is wrong.
WavProblem? wavProblem(Uint8List wav, {required Duration maxDuration}) {
  final l = _layout(wav);
  if (l == null) return WavProblem.notWav;
  final fmt = l.fmtAt;
  if (fmt == null || l.fmtSize < _fmtMinBytes || fmt + _fmtMinBytes > wav.length) {
    return WavProblem.noFormat;
  }
  final formatProblem = _formatProblem(ByteData.sublistView(wav), fmt, l.fmtSize);
  if (formatProblem != null) return formatProblem;
  final data = l.dataAt;
  if (data == null) return WavProblem.noData;
  if (_riffSize(wav) + _riffHeaderBytes != wav.length || data + l.dataSize > wav.length) {
    return WavProblem.sizeMismatch;
  }
  if (l.dataSize < minVoiceWavDataBytes) return WavProblem.tooShort;
  final maxBytes =
      voiceBytesPerSecond * (maxDuration + voiceStopSlack).inMilliseconds ~/
      Duration.millisecondsPerSecond;
  if (l.dataSize > maxBytes) return WavProblem.tooLong;
  return null;
}

WavProblem? _formatProblem(ByteData view, int at, int size) {
  final format = view.getUint16(at, Endian.little);
  // Windows can write the extensible header; its subformat names the real encoding.
  final pcm =
      format == _wavPcmFormat ||
      format == _wavExtensibleFormat &&
          size >= _fmtExtensibleBytes &&
          at + _fmtExtensibleBytes <= view.lengthInBytes &&
          view.getUint16(at + _fmtSubformatOffset, Endian.little) == _wavPcmFormat;
  if (!pcm) return WavProblem.notPcm;
  if (view.getUint16(at + _fmtChannelsOffset, Endian.little) != voiceChannels) {
    return WavProblem.wrongChannels;
  }
  if (view.getUint32(at + _fmtRateOffset, Endian.little) != voiceSampleRate) {
    return WavProblem.wrongRate;
  }
  if (view.getUint16(at + _fmtBitsOffset, Endian.little) != voiceBitsPerSample) {
    return WavProblem.wrongBits;
  }
  return null;
}
