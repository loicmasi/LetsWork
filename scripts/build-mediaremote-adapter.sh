#!/usr/bin/env bash
# Compile MediaRemoteAdapter.framework et le dépose dans Vendor/build/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/mediaremote-adapter"
BUILD="$SRC/build"
OUT="$ROOT/Vendor/build"

cmake -S "$SRC" -B "$BUILD" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --config Release

FRAMEWORK="$(find "$BUILD" -maxdepth 3 -type d -name MediaRemoteAdapter.framework | head -n 1)"
if [[ -z "$FRAMEWORK" ]]; then
  echo "MediaRemoteAdapter.framework introuvable dans $BUILD" >&2
  exit 1
fi

mkdir -p "$OUT"
rm -rf "$OUT/MediaRemoteAdapter.framework"
cp -R "$FRAMEWORK" "$OUT/"
echo "OK : $OUT/MediaRemoteAdapter.framework"
