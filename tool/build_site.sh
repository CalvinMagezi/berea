#!/usr/bin/env bash
# Assembles the public site into build/site: the page plus the app screenshots from docs/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/site"
rm -rf "$out"
mkdir -p "$out/screenshots"
cp "$root"/site/*.html "$root"/site/*.css "$out/"
cp "$root"/docs/screenshots/*.png "$out/screenshots/"
echo "site built at $out"
