#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 -fobjc-arc -c Sources/Bootstrap.m -o build/Bootstrap.o
xcrun swiftc -swift-version 5 -O -emit-library -module-name AccessiGram \
  -target arm64-apple-ios15.0 -sdk "$SDK" Sources/AccessiGram.swift build/Bootstrap.o \
  -framework UIKit -framework Foundation -Xlinker -install_name \
  -Xlinker @rpath/AccessiGram.dylib -o build/AccessiGram.dylib
codesign --force --sign - build/AccessiGram.dylib
