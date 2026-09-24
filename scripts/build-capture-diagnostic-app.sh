#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_ROOT"
swift build --product CaptureDiagnostic

BIN_DIRECTORY=$(swift build --show-bin-path)
APP_DIRECTORY="$PROJECT_ROOT/.build/Phase3ACaptureDiagnostic.app"
INFO_PLIST="$PROJECT_ROOT/scripts/CaptureDiagnostic-Info.plist"
BUNDLE_IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")
EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")

clear_bundle_attributes() {
    xattr -cr "$APP_DIRECTORY"
    # File Provider/Finder can immediately restore this bundle-root attribute.
    xattr -d com.apple.FinderInfo "$APP_DIRECTORY" >/dev/null 2>&1 || true
}

sign_bundle() {
    if signing_output=$(codesign --force --sign - --identifier "$BUNDLE_IDENTIFIER" \
        --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" "$APP_DIRECTORY" 2>&1); then
        printf '%s\n' "$signing_output"
        return
    fi

    case "$signing_output" in
        *"resource fork, Finder information, or similar detritus not allowed"*)
            printf 'Finder metadata reappeared during signing; clearing it and retrying once.\n' >&2
            clear_bundle_attributes
            signing_output=$(codesign --force --sign - --identifier "$BUNDLE_IDENTIFIER" \
                --requirements "=designated => identifier \"$BUNDLE_IDENTIFIER\"" "$APP_DIRECTORY" 2>&1) || {
                printf '%s\n' "$signing_output" >&2
                return 1
            }
            printf '%s\n' "$signing_output"
            ;;
        *)
            printf '%s\n' "$signing_output" >&2
            return 1
            ;;
    esac
}

verify_bundle() {
    if verification_output=$(codesign --verify --deep --strict --verbose=2 "$APP_DIRECTORY" 2>&1); then
        printf '%s\n' "$verification_output"
        return
    fi

    case "$verification_output" in
        *"resource fork, Finder information, or similar detritus not allowed"*)
            printf 'Finder metadata reappeared during verification; clearing it and retrying once.\n' >&2
            clear_bundle_attributes
            verification_output=$(codesign --verify --deep --strict --verbose=2 "$APP_DIRECTORY" 2>&1) || {
                printf '%s\n' "$verification_output" >&2
                return 1
            }
            printf '%s\n' "$verification_output"
            ;;
        *)
            printf '%s\n' "$verification_output" >&2
            return 1
            ;;
    esac
}

case "$APP_DIRECTORY" in
    "$PROJECT_ROOT"/.build/Phase3ACaptureDiagnostic.app) ;;
    *) printf 'Refusing to replace unexpected app path: %s\n' "$APP_DIRECTORY" >&2; exit 1 ;;
esac

# This is generated output only. Recreate it to discard stale Finder/resource metadata.
rm -rf "$APP_DIRECTORY"
mkdir -p "$APP_DIRECTORY/Contents/MacOS"
cp "$INFO_PLIST" "$APP_DIRECTORY/Contents/Info.plist"
cp "$BIN_DIRECTORY/$EXECUTABLE_NAME" "$APP_DIRECTORY/Contents/MacOS/$EXECUTABLE_NAME"
plutil -lint "$APP_DIRECTORY/Contents/Info.plist"

# SwiftPM/Finder may attach provenance or FinderInfo attributes to generated files.
clear_bundle_attributes

# An explicit designated requirement stays tied to the bundle ID across rebuilt binaries.
sign_bundle
printf 'Designated requirement: identifier "%s"\n' "$BUNDLE_IDENTIFIER"
# Bundle metadata can be reattached by Finder/File Provider while the bundle is inspected.
clear_bundle_attributes
verify_bundle

printf 'Built %s\n' "$APP_DIRECTORY"
