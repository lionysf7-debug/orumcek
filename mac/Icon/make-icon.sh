#!/bin/bash
# Uygulama simgesini üretir: make_icon.swift → 1024 PNG → iconset → Resources/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")"

WORK="${TMPDIR:-/tmp}/orumcek-icon"
rm -rf "$WORK"
mkdir -p "$WORK/AppIcon.iconset"

# build.sh'in oluşturduğu modül katmanı varsa onu kullan (SwiftBridging hatası için)
EXTRA=()
[ -d ../build/.swift-overlay/lib/swift ] && EXTRA+=(-resource-dir ../build/.swift-overlay/lib/swift)
xcrun swiftc -O ${EXTRA[@]+"${EXTRA[@]}"} make_icon.swift -o "$WORK/make_icon"
"$WORK/make_icon" "$WORK/icon_1024.png"
cp "$WORK/icon_1024.png" ./icon_1024.png

for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o ../Resources/AppIcon.icns
echo "✓ Resources/AppIcon.icns"
