#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
swift build --product CaptureDiagnostic

BIN_DIRECTORY=$(swift build --show-bin-path)
APP_DIRECTORY="$PROJECT_ROOT/.build/Phase3ACaptureDiagnostic.app"
mkdir -p "$APP_DIRECTORY/Contents/MacOS"
cp "$PROJECT_ROOT/scripts/CaptureDiagnostic-Info.plist" "$APP_DIRECTORY/Contents/Info.plist"
cp "$BIN_DIRECTORY/CaptureDiagnostic" "$APP_DIRECTORY/Contents/MacOS/CaptureDiagnostic"
codesign --force --sign - "$APP_DIRECTORY"

printf 'Built %s\n' "$APP_DIRECTORY"
