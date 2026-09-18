#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ICONSET="$TMP_DIR/AppIcon.iconset"

swift scripts/make-icon.swift Resources/AppIcon.svg "$ICONSET"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$ICONSET/icon_256x256.png" Resources/AppIcon-256.png

echo "Resources/AppIcon.icns"
echo "Resources/AppIcon-256.png"
