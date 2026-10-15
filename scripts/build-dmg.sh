#!/usr/bin/env bash
# =============================================================================
# YonFile — Build macOS .app → .dmg (ຕົວຕິດຕັ້ງ)
#
# ການໃຊ້:
#   SIGNALING_URL=wss://your-server/ws pnpm build:dmg
#   SIGNALING_URL=wss://your-server/ws VERSION=1.0.0 bash scripts/build-dmg.sh
#
# ຕົວແປທີ່ຮັບ (env):
#   SIGNALING_URL  URL ຂອງ signaling server (default: wss://yonfile.example/ws)
#   APP_NAME       ຊື່ .app ຕ້ອງກົງກັບ PRODUCT_NAME (default: YonFile)
#   VOLUME_NAME    ຊື່ທີ່ສະແດງເທິງປະລິມາດ DMG  (default: YonFile)
#   SKIP_BUILD     1 = ໃຊ້ .app ທີ່ build ໄວ້ແລ້ວ, ບໍ່ build ໃໝ່
#   SIGN_IDENTITY  (ທາງເລືອກ) "Developer ID Application: ..." ເພື່ອ sign app + dmg
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SIGNALING_URL="${SIGNALING_URL:-wss://yonfile.example/ws}"
APP_NAME="${APP_NAME:-YonFile}"
VOLUME_NAME="${VOLUME_NAME:-YonFile}"
SKIP_BUILD="${SKIP_BUILD:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

APP_DIR="apps/web_client/build/macos/Build/Products/Release"
APP_PATH="$APP_DIR/${APP_NAME}.app"
STAGE_DIR="build/dmg-root"
OUT_DIR="dist"
OUT_DMG="$OUT_DIR/${APP_NAME}.dmg"

# 1) Build .app
if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "▶ Building macOS app (SIGNALING_URL=$SIGNALING_URL)…"
  (
    cd apps/web_client
    flutter build macos --release --dart-define=SIGNALING_URL="$SIGNALING_URL"
  )
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "✖ ບໍ່ພົບ $APP_PATH — ລອງ build ກ່ອນ (ຫຼືຢ່າໃສ່ SKIP_BUILD=1)" >&2
  exit 1
fi

# 2) (ທາງເລືອກ) ເຊັນ .app
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "▶ Signing app with: $SIGN_IDENTITY"
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
fi

# 3) Staging: ໃສ່ .app + ລິ້ງ /Applications
echo "▶ Staging…"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$OUT_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

# 4) ສ້າງ DMG (compressed, HFS+)
echo "▶ Creating DMG…"
rm -f "$OUT_DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$OUT_DMG"

# 5) (ທາງເລືອກ) ເຊັນ DMG
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "▶ Signing DMG…"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT_DMG"
fi

echo "✔ ສຳເລັດ: $OUT_DMG"
ls -lh "$OUT_DMG"
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "ℹ ໝາຍເຫດ: ໄຟລ໌ນີ້ sign ແບບ ad-hoc — ຜູ້ໃຊ້ຕ້ອງ ຄລິກຂວາ → Open ຄັ້ງທຳອິດ ຫຼື"
  echo "   xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app"
fi
