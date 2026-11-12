#!/usr/bin/env bash
# Berea writes nothing and runs no model. This fails when a generative or voice package, a
# microphone permission or a model runtime's name comes back into the code.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
fail=0

packages='flutter_edge_ai|flutter_gemma|sherpa_onnx|audioplayers|connectivity_plus|llama|onnxruntime|tflite|whisper|^  record:'
if grep -nE "^  ($packages)" pubspec.lock packages/harness/pubspec.lock 2>/dev/null; then
  echo "A model or voice package is in a pubspec.lock." >&2
  fail=1
fi

if grep -rn "RECORD_AUDIO\|FOREGROUND_SERVICE" android/app/src/main/AndroidManifest.xml; then
  echo "The Android manifest asks for the microphone or a foreground service." >&2
  fail=1
fi

words='Ollama|ollama|Gemma|gemma|LiteRT|LlmEngine|PromptBuilder|EdgeAiEngine|OllamaEngine'
if grep -rnEw "$words" lib packages/harness/lib packages/harness/bin; then
  echo "A model runtime's name is in the code." >&2
  fail=1
fi

exit $fail
