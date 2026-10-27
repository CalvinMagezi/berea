#!/usr/bin/env bash
# Local release: the eval needs a model, which CI does not have, so releases are cut here.
# Usage: tool/release.sh 0.2.0
set -euo pipefail

version="${1:?usage: tool/release.sh <version, e.g. 0.2.0>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean." >&2
  exit 1
fi
grep -q "^## $version" CHANGELOG.md || { echo "Add a '## $version' section to CHANGELOG.md first." >&2; exit 1; }

echo "Checking that the model release the app downloads from exists"
model_tag="$(grep -o 'releases/download/model-[a-z0-9.-]*' lib/models.dart | head -1 | cut -d/ -f3 || true)"
[[ -n "$model_tag" ]] || { echo "lib/models.dart names no model release." >&2; exit 1; }
gh release view "$model_tag" --json assets --jq '.assets[].name' | grep -q '\.litertlm$' \
  || { echo "Release $model_tag has no .litertlm file; the app would fail to download its model." >&2; exit 1; }

echo "Building the Bible database and the lexicon pack"
(cd packages/harness && dart pub get >/dev/null && dart run bin/build_db.dart && dart run bin/build_lexicon_pack.dart)

echo "Placing SHA-256 checked PDFium builds for the hook"
tool/pin_pdfium.sh mac-arm64 mac-x64 android-arm64

echo "Running checks"
(cd packages/harness && dart analyze --fatal-infos && dart test)
flutter analyze --fatal-infos
flutter test

echo "Checking the site's live reference check against the harness"
(cd packages/harness && dart run bin/export_site.dart)
node site/check/selftest.mjs
if [[ -n "$(git status --porcelain -- site/data)" ]]; then
  echo "site/data changed when regenerated from this database. Commit it, then release." >&2
  exit 1
fi

echo "Running the grounding eval against Ollama (gemma4:e2b)"
mkdir -p "$root/build"
(cd packages/harness && dart run bin/eval.dart --tier mid | tee "$root/build/eval-$version.txt")
echo "Running the word study eval against Ollama (gemma4:e2b)"
(cd packages/harness && dart run bin/eval.dart --tier mid --words | tee -a "$root/build/eval-$version.txt")

echo "Building release artifacts"
[[ -f android/key.properties ]] || { echo "android/key.properties is missing; see android/key.properties.example." >&2; exit 1; }
flutter build apk --release --target-platform android-arm64 --build-name "$version"
cp build/app/outputs/flutter-apk/app-release.apk "build/berea-$version-android-arm64.apk"
# A fixed name too, so the site's releases/latest/download link always finds the newest APK.
cp build/app/outputs/flutter-apk/app-release.apk build/berea-android-arm64.apk
flutter build macos --release --build-name "$version"
ditto -c -k --keepParent build/macos/Build/Products/Release/berea.app "build/berea-$version-macos.zip"
cp "build/berea-$version-macos.zip" build/berea-macos.zip

git tag -a "v$version" -m "Berea $version"
echo
echo "Tagged v$version. Publish with:"
echo "  git push origin v$version"
echo "  gh release create v$version --latest --title 'Berea $version' --notes-file <(sed -n '/^## $version/,/^## /p' CHANGELOG.md | sed '\$d') \\"
echo "    build/berea-$version-android-arm64.apk build/berea-android-arm64.apk \\"
echo "    build/berea-$version-macos.zip build/berea-macos.zip \\"
echo "    build/lexicon-lsj.sqlite build/eval-$version.txt"
