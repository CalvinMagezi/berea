#!/usr/bin/env bash
# Assembles the public site into build/site: everything under site/, plus the app screenshots
# the page shows, from docs/. The check's Bible data in site/data is written by
# packages/harness/bin/export_site.dart and committed, because CI has no Bible database.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/site"
rm -rf "$out"
mkdir -p "$out/screenshots"
cp -R "$root"/site/. "$out/"
rm -f "$out/check/selftest.mjs" "$out/data/fixture.json"
shots="$root/docs/screenshots/bible-first-shell"
for shot in 1-bible 2-plans 3-study 4-prayer 5-notes 6-selection; do
  cp "$shots/a32-$shot.png" "$out/screenshots/bible-first-shell-${shot#*-}.png"
done
cp "$shots/mac-1-bible-dark.png" "$out/screenshots/mac-bible.png"
echo "site built at $out"
