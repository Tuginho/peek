#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"

rm -rf dist
mkdir -p dist

DEV_ID_IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)"

if [ -n "$DEV_ID_IDENTITY" ]; then
    USED_DEVELOPER_ID=1
    PEEK_ARCHS="arm64 x86_64" PEEK_OUT_DIR=dist PEEK_IDENTITY_MATCH="Developer ID Application" \
        PEEK_HARDENED_RUNTIME=1 ./scripts/build.sh
else
    USED_DEVELOPER_ID=0
    PEEK_ARCHS="arm64 x86_64" PEEK_OUT_DIR=dist PEEK_IDENTITY_MATCH="Developer ID Application" \
        ./scripts/build.sh
    cat >&2 <<'EOF'

warning: no "Developer ID Application" signing identity found.
warning: dist/Peek.app is ad-hoc signed and NOT notarized.
warning: Gatekeeper will block the first launch until the user allows it
warning: manually (System Settings -> Privacy & Security -> "Open Anyway",
warning: or by running: xattr -dr com.apple.quarantine /Applications/Peek.app).

EOF
fi

APP="dist/Peek.app"
BIN="$APP/Contents/MacOS/Peek"

ARCHS_FOUND="$(lipo -archs "$BIN")"
echo "binary architectures: $ARCHS_FOUND"
case " $ARCHS_FOUND " in
    *" arm64 "*"x86_64"*|*" x86_64 "*"arm64"*) ;;
    *)
        echo "error: expected a universal (arm64 + x86_64) binary, got: $ARCHS_FOUND" >&2
        exit 1
        ;;
esac

ZIP="dist/Peek-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "$USED_DEVELOPER_ID" = "1" ] && [ -n "${PEEK_NOTARY_PROFILE:-}" ]; then
    echo "submitting $ZIP for notarization with profile $PEEK_NOTARY_PROFILE..."
    xcrun notarytool submit "$ZIP" --keychain-profile "$PEEK_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    spctl -a -vv "$APP"
elif [ "$USED_DEVELOPER_ID" = "1" ]; then
    echo "warning: dist/Peek.app is signed with a Developer ID but PEEK_NOTARY_PROFILE is not set; $ZIP is signed but NOT notarized." >&2
fi

SIZE="$(du -h "$ZIP" | cut -f1 | tr -d ' ')"
SHA_LINE="$(shasum -a 256 "$ZIP")"

echo
echo "zip: $ZIP"
echo "size: $SIZE"
echo "sha256: $SHA_LINE"

# The changelog section for this version, extracted the same way the
# --notes-file argument below extracts it: from the "## [$VERSION]" heading
# up to (but not including) the next "## [" heading, or to the end of the
# file if this is the most recent entry (there is no next heading to stop
# at, so a plain sed range would swallow the file's last line — awk handles
# that correctly).
NOTES_CMD_TEMPLATE=$(cat <<'TPL'
gh release create "vVERSION_PLACEHOLDER" "ZIP_PLACEHOLDER" --title "Peek VERSION_PLACEHOLDER" --notes-file <(awk -v ver="VERSION_PLACEHOLDER" '$0 ~ "^## \\[" ver "\\]" { found=1; print; next } found && /^## \[/ { exit } found { print }' CHANGELOG.md)
TPL
)
NOTES_CMD="${NOTES_CMD_TEMPLATE//VERSION_PLACEHOLDER/$VERSION}"
NOTES_CMD="${NOTES_CMD//ZIP_PLACEHOLDER/$ZIP}"

echo
echo "Follow-up (not executed):"
echo "$NOTES_CMD"
