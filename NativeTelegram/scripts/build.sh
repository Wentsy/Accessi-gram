#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
xcodebuild -project AccessiGramNative.xcodeproj -scheme AccessiGramNative -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p dist/Payload
cp -R build/Build/Products/Release-iphoneos/AccessiGramNative.app dist/Payload/
if [[ -n "${TELEGRAM_APNS_SANDBOX:-}" ]]; then
  plutil -replace TelegramAPNsIsSandbox -bool "$TELEGRAM_APNS_SANDBOX" dist/Payload/AccessiGramNative.app/Info.plist
fi
if [[ -n "${TELEGRAM_API_ID:-}" && -n "${TELEGRAM_API_HASH:-}" ]]; then
  plutil -replace TelegramAPIID -string "$TELEGRAM_API_ID" dist/Payload/AccessiGramNative.app/Info.plist
  plutil -replace TelegramAPIHash -string "$TELEGRAM_API_HASH" dist/Payload/AccessiGramNative.app/Info.plist
fi
rm -f dist/AccessiGramNative-unsigned.ipa
(cd dist && zip -qyr AccessiGramNative-unsigned.ipa Payload)
echo "Unsigned IPA: dist/AccessiGramNative-unsigned.ipa"
