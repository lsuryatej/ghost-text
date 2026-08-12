#!/bin/bash
# Assemble and sign Ghost Text.app.
#
# The signing identity is not cosmetic: TCC keys Accessibility and Input
# Monitoring grants to the code-signing designated requirement. Signing every
# build with the same identity + bundle ID is what lets the grant survive a
# rebuild. Ad-hoc signing silently invalidates it on every cdhash change.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Ghost Text.app"
CONFIG="${GHOST_CONFIG:-release}"
IDENTITY="${GHOST_SIGN_IDENTITY:-Apple Development: lsuryatej@icloud.com (DLD26YNNVL)}"

swift build -c "$CONFIG" --product GhostTextApp

BIN_DIR="$ROOT/.build/$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GhostTextApp" "$APP/Contents/MacOS/GhostText"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# MLX ships its Metal shaders in a SwiftPM resource bundle. A hand-assembled
# .app does not pick these up automatically and MLX fails at runtime without
# them, so copy every bundle SwiftPM produced.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
	cp -R "$bundle" "$APP/Contents/Resources/"
	echo "bundled resource: $(basename "$bundle")"
done
shopt -u nullglob

codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"

echo "built: $APP"
