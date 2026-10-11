#!/usr/bin/env bash
# Assembles the public site into build/site: the page, its script and images, and the app
# screenshots from docs/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/build/site"
rm -rf "$out"
mkdir -p "$out/screenshots" "$out/images"
cp "$root"/site/*.html "$root"/site/*.css "$root"/site/*.js "$out/"
cp "$root"/site/images/* "$out/images/"
cp "$root"/docs/screenshots/*.png "$out/screenshots/"
echo "site built at $out"
