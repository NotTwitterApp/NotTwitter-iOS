#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$APP_ROOT/.." && pwd)"
THEOS_DIR="${THEOS:-$ROOT/_build/theos}"
SDK_DIR="${SDKROOT:-$ROOT/_build/sdks/iPhoneOS16.5.sdk}"
LDID_DIR="$ROOT/_build/bin"
INSTALL=0
UDID=""
XTOOL_BUNDLE_ID="${XTOOL_BUNDLE_ID:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--install] [--udid UDID]

Builds the standalone Not Twitter ATProto app as an IPA.

Options:
  --install    Install the built IPA with xtool after packaging.
  --udid UDID  Target device UDID for xtool install.

Environment:
  XTOOL_BUNDLE_ID  Optional explicit bundle ID rewrite before xtool signing.
                   Leave unset for normal xtool installs so xtool only rewrites once.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=1
      shift
      ;;
    --udid)
      UDID="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -d "$THEOS_DIR" ]] || { echo "Theos not found at $THEOS_DIR." >&2; exit 2; }
[[ -d "$SDK_DIR" ]] || { echo "iPhoneOS SDK not found at $SDK_DIR." >&2; exit 2; }

: "${TRANSLATION_SDKROOT:?Set TRANSLATION_SDKROOT to an iOS 18+ SDK for the translation framework}"

export THEOS="$THEOS_DIR"
export SDKROOT="$SDK_DIR"
export PATH="$LDID_DIR:$PATH"
export TARGET=iphone:clang:16.5:14.0

make -C "$APP_ROOT" clean package

IPA="$(find "$APP_ROOT/packages" -type f -name '*.ipa' ! -name '*.xtool*.ipa' | sort -V | tail -n1)"
[[ -f "$IPA" ]] || { echo "No IPA produced in $APP_ROOT/packages." >&2; exit 1; }

echo "Built $IPA"

if [[ "$INSTALL" -eq 1 ]]; then
  INSTALL_IPA="$IPA"
  if [[ -n "$XTOOL_BUNDLE_ID" ]]; then
    TEMP_DIR="$(mktemp -d)"
    XTOOL_IPA="${IPA%.ipa}.xtool.ipa"
    unzip -q "$IPA" -d "$TEMP_DIR"
    INFO_PLIST="$(find "$TEMP_DIR/Payload" -maxdepth 2 -name Info.plist | head -n1)"
    [[ -f "$INFO_PLIST" ]] || { echo "No Info.plist found in IPA." >&2; exit 1; }
    if command -v plistutil >/dev/null 2>&1; then
      plistutil -i "$INFO_PLIST" -o "$INFO_PLIST.xml" -f xml >/dev/null
      mv "$INFO_PLIST.xml" "$INFO_PLIST"
    fi
    perl -0pi -e "s|<key>CFBundleIdentifier</key>\\s*<string>[^<]+</string>|<key>CFBundleIdentifier</key>\\n\\t<string>${XTOOL_BUNDLE_ID}</string>|; s|<key>CFBundleURLName</key>\\s*<string>[^<]+</string>|<key>CFBundleURLName</key>\\n\\t\\t\\t<string>${XTOOL_BUNDLE_ID}</string>|" "$INFO_PLIST"
    rm -f "$XTOOL_IPA"
    (cd "$TEMP_DIR" && zip -qr "$XTOOL_IPA" Payload)
    rm -rf "$TEMP_DIR"
    INSTALL_IPA="$XTOOL_IPA"
    echo "Prepared xtool bundle $XTOOL_BUNDLE_ID at $INSTALL_IPA"
  fi

  if [[ -n "$UDID" ]]; then
    xtool install --udid "$UDID" --usb "$INSTALL_IPA"
  else
    xtool install --usb "$INSTALL_IPA"
  fi
fi
