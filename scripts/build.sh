#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG=${CONFIG:-release}
OUT_DIR=${PEEK_OUT_DIR:-build}
IDENTITY_MATCH=${PEEK_IDENTITY_MATCH:-Apple Development}

# Space-separated list of architectures, e.g. PEEK_ARCHS="arm64 x86_64" for a
# universal build. Empty (default) builds for the host architecture only,
# same as before this variable existed.
ARCH_FLAGS=()
for arch in ${PEEK_ARCHS:-}; do
    ARCH_FLAGS+=(--arch "$arch")
done

swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_PATH="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)/Peek"

APP="$OUT_DIR/Peek.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH" "$APP/Contents/MacOS/Peek"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

if [ ! -f "Resources/AppIcon.icns" ]; then
    echo "error: Resources/AppIcon.icns is missing; run scripts/make-icon.sh to generate it" >&2
    exit 1
fi
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${PEEK_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    # `|| true`: without an identity grep exits 1 and pipefail would abort before the ad-hoc fallback.
    IDENTITY="$(security find-identity -v -p codesigning | grep "$IDENTITY_MATCH" | head -1 | sed -E 's/.*[0-9]\) ([A-F0-9]+) .*/\1/' || true)"
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY="-"
    echo "warning: no signing identity found, ad-hoc signing (-); this resets the macOS privacy grants on every build" >&2
fi

CODESIGN_FLAGS=(--force --sign "$IDENTITY" --identifier com.tugay.peek)
if [ "${PEEK_HARDENED_RUNTIME:-}" = "1" ]; then
    CODESIGN_FLAGS+=(--options runtime --timestamp)
fi

codesign "${CODESIGN_FLAGS[@]}" "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "^Identifier|^Authority|^TeamIdentifier"

echo "$APP"
