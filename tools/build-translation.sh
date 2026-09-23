#!/usr/bin/env bash
set -Eeuo pipefail
APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TRANSLATION_SDKROOT:?Set TRANSLATION_SDKROOT to an iOS 18 or newer SDK with Swift interfaces}"
SWIFTC="${SWIFTC:-swiftc}"
DARWIN_LD="${DARWIN_LD:-ld64.lld}"
LINK_SDK="${TRANSLATION_LINK_SDKROOT:-$TRANSLATION_SDKROOT}"
OUTPUT="$1/NFBTranslation.framework"
mkdir -p "$OUTPUT"
BRIDGE_OBJECT="$APP_ROOT/.theos/NFBTranslation.o"
"$SWIFTC" -emit-object -parse-as-library -whole-module-optimization -O \
  -module-name NFBTranslation -target arm64-apple-ios18.0 \
  -module-cache-path "${NFB_TRANSLATION_MODULE_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/not-twitter-swift}" \
  -sdk "$TRANSLATION_SDKROOT" \
  -resource-dir "${TRANSLATION_SWIFT_RESOURCES:-$TRANSLATION_SDKROOT/usr/lib/swift}" \
  -Xfrontend -enable-cross-import-overlays \
  -Xfrontend -disable-autolinking-runtime-compatibility \
  -Xfrontend -disable-readonly-static-objects \
  "$APP_ROOT/NFBTranslationPolicy.swift" "$APP_ROOT/NFBTranslationBridge.swift" \
  -o "$BRIDGE_OBJECT"
"$DARWIN_LD" -dylib -arch arm64 -platform_version ios 18.0 18.0 \
  -syslibroot "$LINK_SDK" \
  -L "$LINK_SDK/usr/lib/swift" \
  -install_name @rpath/NFBTranslation.framework/NFBTranslation \
  "$BRIDGE_OBJECT" -framework Translation -framework _Translation_SwiftUI -lSystem -lobjc -o "$OUTPUT/NFBTranslation"
cat > "$OUTPUT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.nottwitter.translation</string>
<key>CFBundleName</key><string>NFBTranslation</string>
<key>CFBundleExecutable</key><string>NFBTranslation</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>18.0</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
</dict></plist>
PLIST
ldid -S "$OUTPUT/NFBTranslation"
