#!/usr/bin/env bash
# pdfium_dart's build hook downloads PDFium with no hash check, but skips the download when the
# library is already at its output path. This puts a SHA-256 checked copy there first.
# Usage: tool/pin_pdfium.sh <target>...   targets: android-arm64 linux-x64 win-x64 mac-arm64 mac-x64
# Run it after `flutter pub get` and again after `flutter clean`.
set -euo pipefail

release_tag='chromium/7811'
hook_version='0.3.1'
root="$(cd "$(dirname "$0")/.." && pwd)"
out_root="$root/.dart_tool/hooks_runner/shared/pdfium_dart/build/${release_tag/\//_}"

# A newer hook may fetch another release or write elsewhere; review it before trusting this pin.
if ! grep -A7 '^  pdfium_dart:' "$root/pubspec.lock" | grep -q "version: \"$hook_version\""; then
  echo "pdfium_dart is not $hook_version in pubspec.lock; review its hook and update this script." >&2
  exit 1
fi

sha256_of() {
  if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

[[ $# -gt 0 ]] || { echo "usage: tool/pin_pdfium.sh <target>..." >&2; exit 1; }
for target in "$@"; do
  case "$target" in
    android-arm64) sha=f51539cadeb5135534305b8bdf8685ce2fbe9991dbbc5b35f553108411b9ed14; member=lib/libpdfium.so ;;
    linux-x64) sha=e76e0a37aefb843d56f04657475ce612157021b1ebc53d801f2fbfcc537ccf64; member=lib/libpdfium.so ;;
    win-x64) sha=2e7af12674ac3716cb0e20369bb9fb269ceadfa2f0b0597097a520e6834175a0; member=bin/pdfium.dll ;;
    mac-arm64) sha=f9bbf1ebdc459e5f5ff25b2d457cc21db55ebfc0cf3d89fc1b90ce5445dac394; member=lib/libpdfium.dylib ;;
    mac-x64) sha=b31565aacda1f84393cd98438b06b49f21124888785e7dd1ddf015fa4406bd80; member=lib/libpdfium.dylib ;;
    *) echo "unknown target $target" >&2; exit 1 ;;
  esac
  tmp="$(mktemp -d)"
  url="https://github.com/bblanchon/pdfium-binaries/releases/download/${release_tag/\//%2F}/pdfium-$target.tgz"
  curl -sSfL --retry 3 -o "$tmp/pdfium.tgz" "$url"
  actual="$(sha256_of "$tmp/pdfium.tgz")"
  if [[ "$actual" != "$sha" ]]; then
    echo "PDFium $target: SHA-256 $actual does not match the pin $sha" >&2
    rm -rf "$tmp"
    exit 1
  fi
  tar xzf "$tmp/pdfium.tgz" -C "$tmp" "$member"
  mkdir -p "$out_root/$target"
  cp "$tmp/$member" "$out_root/$target/$(basename "$member")"
  rm -rf "$tmp"
  echo "PDFium $target pinned at $out_root/$target"
done
