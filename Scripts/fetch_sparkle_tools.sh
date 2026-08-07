#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/Scripts/sparkle-tools"
SPARKLE_VERSION="2.9.5"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"

if [ -x "$TOOLS_DIR/generate_appcast" ] && [ -x "$TOOLS_DIR/sign_update" ] && [ -x "$TOOLS_DIR/generate_keys" ]; then
    exit 0
fi

echo "Fetching Sparkle $SPARKLE_VERSION command-line tools..."
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

curl -sL "$URL" -o "$TMP_DIR/Sparkle.tar.xz"
tar -xf "$TMP_DIR/Sparkle.tar.xz" -C "$TMP_DIR"

mkdir -p "$TOOLS_DIR"
cp "$TMP_DIR/bin/generate_keys" "$TMP_DIR/bin/sign_update" "$TMP_DIR/bin/generate_appcast" "$TOOLS_DIR/"
chmod +x "$TOOLS_DIR"/*

echo "Sparkle tools installed at $TOOLS_DIR"
