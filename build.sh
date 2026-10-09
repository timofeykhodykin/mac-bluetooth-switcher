#!/bin/bash
# Builds build/Bluetooth Switcher.app (universal binary). Only the Xcode Command Line Tools are needed.
# Usage: ./build.sh            — build
#        ./build.sh install    — build, copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")"

NAME="Bluetooth Switcher"
EXEC="BluetoothSwitcher"
APP="build/$NAME.app"
MIN_OS="13.0"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

for ARCH in arm64 x86_64; do
    swiftc -O -parse-as-library \
        -target "$ARCH-apple-macos$MIN_OS" \
        -import-objc-header Sources/BridgingHeader.h \
        -framework IOBluetooth \
        -o "build/obj/$EXEC-$ARCH" \
        Sources/*.swift
done

lipo -create -output "$APP/Contents/MacOS/$EXEC" build/obj/"$EXEC"-*
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x "$EXEC" || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" /Applications/
    open "/Applications/$NAME.app"
    echo "Installed to /Applications and launched"
fi
