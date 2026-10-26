#!/usr/bin/env bash
# Phase de build Xcode : embarque MediaRemoteAdapter.framework et son script perl dans l'app,
# s'ils ont été compilés avec `make adapter`. Sinon, l'app utilise le repli AppleScript.
set -euo pipefail

FRAMEWORK="$SRCROOT/Vendor/build/MediaRemoteAdapter.framework"
SCRIPT="$SRCROOT/Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl"
FRAMEWORKS_DIR="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
RESOURCES_DIR="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"

if [[ ! -d "$FRAMEWORK" || ! -f "$SCRIPT" ]]; then
  echo "note: mediaremote-adapter non compilé (make adapter) : repli AppleScript."
  rm -rf "$FRAMEWORKS_DIR/MediaRemoteAdapter.framework" "$RESOURCES_DIR/mediaremote-adapter.pl"
  exit 0
fi

mkdir -p "$FRAMEWORKS_DIR" "$RESOURCES_DIR"
rsync -a --delete "$FRAMEWORK" "$FRAMEWORKS_DIR/"
cp "$SCRIPT" "$RESOURCES_DIR/"

# Tout code embarqué doit être signé avec le hardened runtime ; horodatage requis pour la notarisation.
TIMESTAMP="--timestamp=none"
if [[ "$CONFIGURATION" == "Release" ]]; then
  TIMESTAMP="--timestamp"
fi
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --options runtime "$TIMESTAMP" \
  "$FRAMEWORKS_DIR/MediaRemoteAdapter.framework"
