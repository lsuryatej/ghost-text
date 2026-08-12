#!/bin/bash
# Assemble and sign Ghost Text.app.
#
# Two things here are load-bearing.
#
# The signing identity: TCC keys Accessibility and Input Monitoring grants to the
# code-signing designated requirement. Signing every build with the same identity
# and bundle ID is what lets a grant survive a rebuild. Ad-hoc signing silently
# invalidates it on every cdhash change.
#
# xcodebuild rather than `swift build`: mlx-swift has no Metal-shader compile step
# outside Xcode. Plain `swift build` compiles and links fine, then crashes at first
# use with "Failed to load the default metallib". Only xcodebuild invokes the Metal
# compiler that produces it. See BENCH.md.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Ghost Text.app"
CONFIG="${GHOST_CONFIG:-Release}"
DERIVED="$ROOT/.build/xcode"
IDENTITY="${GHOST_SIGN_IDENTITY:-Apple Development: lsuryatej@icloud.com (DLD26YNNVL)}"

if ! xcrun --find metal >/dev/null 2>&1; then
	echo "Metal toolchain missing. Run once, then re-run this script:"
	echo "  xcodebuild -downloadComponent MetalToolchain"
	exit 1
fi

xcodebuild build \
	-scheme GhostTextApp \
	-destination 'platform=macOS' \
	-configuration "$CONFIG" \
	-derivedDataPath "$DERIVED" \
	-skipPackagePluginValidation \
	-skipMacroValidation \
	>/dev/null

PRODUCTS="$DERIVED/Build/Products/$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/GhostTextApp" "$APP/Contents/MacOS/GhostText"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# MLX ships its compiled Metal shaders in a SwiftPM resource bundle. A
# hand-assembled .app does not pick these up, and MLX fails at runtime without
# them, so copy every bundle the build produced.
shopt -s nullglob
for bundle in "$PRODUCTS"/*.bundle; do
	cp -R "$bundle" "$APP/Contents/Resources/"
	echo "bundled resource: $(basename "$bundle")"
done
shopt -u nullglob

if [ ! -f "$APP/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" ]; then
	echo "WARNING: default.metallib missing — the app will crash on first inference"
fi

codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"

echo "built: $APP"
