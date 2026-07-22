#!/bin/bash
set -e  # exit immediately if any command fails

# ============================================================================
# BrowserLink Release Script
# ============================================================================
# Automates: Archive -> Export -> Zip -> Sign & generate appcast
#
# What this does NOT do (still manual, on purpose):
#   - Bumping the version number in Xcode (do this first, before running)
#   - Uploading the zip to GitHub Releases
#   - Fixing the <enclosure url> in appcast.xml to match the real GitHub URL
#   - Committing/pushing appcast.xml to your repo
# These are left manual because they involve external services (GitHub) and
# a version bump is a deliberate decision, not something to automate blindly.
#
# USAGE:
#   ./release.sh 1.1.0
#
# ============================================================================

if [ -z "$1" ]; then
    echo "❌ Usage: ./release.sh <version>"
    echo "   Example: ./release.sh 1.1.0"
    exit 1
fi

VERSION="$1"

# ---- CONFIGURE THESE PATHS FOR YOUR MACHINE ----
PROJECT_PATH="$HOME/Documents/browserlink/BrowserLink.xcodeproj"
SCHEME_NAME="BrowserLink"
SPARKLE_TOOLS_DIR="/tmp/sparkle-tools/bin"
RELEASES_DIR="$HOME/Desktop/BrowserLink-releases"
# --------------------------------------------------

RELEASE_FOLDER="$RELEASES_DIR/$VERSION"
ARCHIVE_PATH="$RELEASE_FOLDER/BrowserLink.xcarchive"
EXPORT_PATH="$RELEASE_FOLDER/export"
ZIP_NAME="BrowserLink-$VERSION.zip"

echo "🚀 Building BrowserLink v$VERSION"
echo "   Output folder: $RELEASE_FOLDER"
echo ""

mkdir -p "$RELEASE_FOLDER"

# ---- 1. Make sure Sparkle tools are available ----
if [ ! -f "$SPARKLE_TOOLS_DIR/generate_appcast" ]; then
    echo "📥 Sparkle tools not found — downloading..."
    curl -L https://github.com/sparkle-project/Sparkle/releases/latest/download/Sparkle-for-Swift-Package-Manager.zip -o /tmp/sparkle-tools.zip
    unzip -oq /tmp/sparkle-tools.zip -d /tmp/sparkle-tools
    echo "✅ Sparkle tools ready"
fi

# ---- 2. Archive ----
echo ""
echo "📦 Archiving (this can take a minute)..."
xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    | xcpretty || true  # xcpretty is optional formatting; falls through fine without it

if [ ! -d "$ARCHIVE_PATH" ]; then
    echo "❌ Archive failed — check the xcodebuild output above."
    exit 1
fi
echo "✅ Archive complete: $ARCHIVE_PATH"

# ---- 3. Export the .app from the archive ----
echo ""
echo "📤 Exporting .app..."

# A minimal export options plist for "Copy App" style direct distribution
# (no notarization, no Developer ID signing requirements).
EXPORT_OPTIONS_PLIST="$RELEASE_FOLDER/ExportOptions.plist"
cat > "$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    || {
        echo "⚠️  Standard export failed (this can happen without a paid Developer ID)."
        echo "    Falling back to direct copy from the archive instead..."
        mkdir -p "$EXPORT_PATH"
        cp -R "$ARCHIVE_PATH/Products/Applications/BrowserLink.app" "$EXPORT_PATH/"
    }

if [ ! -d "$EXPORT_PATH/BrowserLink.app" ]; then
    echo "❌ Export failed — no BrowserLink.app found at $EXPORT_PATH"
    exit 1
fi
echo "✅ Exported: $EXPORT_PATH/BrowserLink.app"

# ---- 4. Zip it correctly (ditto, not plain zip, to preserve bundle structure) ----
echo ""
echo "🗜  Zipping..."
cd "$EXPORT_PATH"
ditto -c -k --sequesterRsrc --keepParent BrowserLink.app "$RELEASE_FOLDER/$ZIP_NAME"
echo "✅ Created: $RELEASE_FOLDER/$ZIP_NAME"

# ---- 5. Sign + generate appcast ----
echo ""
echo "🔏 Signing and generating appcast..."
"$SPARKLE_TOOLS_DIR/generate_appcast" "$RELEASE_FOLDER"
echo "✅ appcast.xml generated in $RELEASE_FOLDER"

# ---- Done — print next manual steps ----
echo ""
echo "🎉 Done! Local build complete for v$VERSION"
echo ""
echo "-----------------------------------------------------------"
echo "NEXT STEPS (still manual):"
echo "1. Go to: https://github.com/jacksonvil-s/browserlink/releases/new"
echo "   Tag: v$VERSION"
echo "   Upload: $RELEASE_FOLDER/$ZIP_NAME"
echo ""
echo "2. After publishing, copy the asset's real download URL and check"
echo "   that it matches the <enclosure url=...> line in:"
echo "   $RELEASE_FOLDER/appcast.xml"
echo ""
echo "3. Copy that appcast.xml into your repo root and push:"
echo "   cp $RELEASE_FOLDER/appcast.xml /path/to/your/repo/appcast.xml"
echo "   cd /path/to/your/repo && git add appcast.xml && git commit -m 'Release $VERSION' && git push"
echo "-----------------------------------------------------------"
