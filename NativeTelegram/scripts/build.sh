#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
xcodebuild -project AccessiGramNative.xcodeproj -scheme AccessiGramNative -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p dist/Payload
cp -R build/Build/Products/Release-iphoneos/AccessiGramNative.app dist/Payload/
(cd dist && zip -qyr AccessiGramNative-unsigned.ipa Payload)
echo "Unsigned IPA: dist/AccessiGramNative-unsigned.ipa"
