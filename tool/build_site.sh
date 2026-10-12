#!/usr/bin/env bash
# Assembles the public site into build/site: everything under site/, plus the app screenshots
# from docs/. The check's Bible data in site/data is written by
# packages/harness/bin/export_site.dart and committed, because CI has no Bible database.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/site"
rm -rf "$out"
mkdir -p "$out/screenshots"
cp -R "$root"/site/. "$out/"
rm -f "$out/check/selftest.mjs" "$out/data/fixture.json"
cp "$root"/docs/screenshots/*.png "$out/screenshots/"
echo "site built at $out"
