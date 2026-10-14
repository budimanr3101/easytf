#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
cargo build --offline --release --bin easytf-desktop
swift build --package-path native --build-system native -c release
BIN_DIR="$(swift build --package-path native --build-system native -c release --show-bin-path)"
APP="native/build/EasyTF.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EasyTFDesktop" "$APP/Contents/MacOS/EasyTF.new"
mv "$APP/Contents/MacOS/EasyTF.new" "$APP/Contents/MacOS/EasyTF"
cp target/release/easytf-desktop "$APP/Contents/Resources/easytf-desktop.new"
mv "$APP/Contents/Resources/easytf-desktop.new" "$APP/Contents/Resources/easytf-desktop"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>EasyTF</string>
<key>CFBundleDisplayName</key><string>EasyTF</string>
<key>CFBundleIdentifier</key><string>com.budimanrahardjo.easytf</string>
<key>CFBundleExecutable</key><string>EasyTF</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/Resources/easytf-desktop"
codesign --force --sign - "$APP"
echo "Built $APP"
