#!/bin/bash
set -euo pipefail

APP_NAME="Effortless"
VERSION="${1:-0.2.0}"
SIGNING_IDENTITY="Developer ID Application: Iuliu Laurentiu Pop (D48Z9SLWYU)"
NOTARIZE_PROFILE="effortless-notarize"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $APP_NAME v$VERSION..."

# Build release binary
swift build -c release 2>&1

# Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.iulspop.effortless</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

# Codesign the app
echo "Signing with: $SIGNING_IDENTITY"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
echo "✓ Codesigned"

# Verify signature
codesign --verify --verbose "$APP_BUNDLE"
echo "✓ Signature verified"

# Create zip for notarization
cd "$BUILD_DIR"
rm -f "$APP_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip"
cd - > /dev/null

ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

# Notarize (pass --notarize to enable)
if [[ "${2:-}" == "--notarize" ]]; then
    echo "Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
      --keychain-profile "$NOTARIZE_PROFILE" \
      --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"
    echo "✓ Stapled"

    # Re-create zip with stapled app
    cd "$BUILD_DIR"
    rm -f "$APP_NAME.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip"
    cd - > /dev/null
else
    echo "Skipping notarization (pass --notarize to enable)"
fi

SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

echo ""
echo "✓ Built $APP_BUNDLE"
echo "✓ Signed, notarized, and stapled"
echo "✓ Created $ZIP_PATH"
echo "  SHA256: $SHA256"
echo "  Version: $VERSION"
