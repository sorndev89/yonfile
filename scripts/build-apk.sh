#!/usr/bin/env bash
# =============================================================================
# YonFile — Build Android release APK → dist/YonFile.apk
#
# ການໃຊ້:
#   SIGNALING_URL=wss://your-server/ws pnpm build:apk
#
# ຕົວແປທີ່ຮັບ (env):
#   SIGNALING_URL  URL ຂອງ signaling server (default: wss://yonfile.example/ws)
#   APK_NAME       ຊື່ໄຟລ໌ APK ທີ່ຈະອອກ    (default: YonFile)
#   SKIP_BUILD     1 = ໃຊ້ APK ທີ່ build ໄວ້ແລ້ວ, ບໍ່ build ໃໝ່
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SIGNALING_URL="${SIGNALING_URL:-wss://yonfile.example/ws}"
APK_NAME="${APK_NAME:-YonFile}"
SKIP_BUILD="${SKIP_BUILD:-0}"

SRC_APK="apps/web_client/build/app/outputs/flutter-apk/app-release.apk"
OUT_DIR="dist"
OUT_APK="$OUT_DIR/${APK_NAME}.apk"

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "▶ Building Android APK (SIGNALING_URL=$SIGNALING_URL)…"
  (
    cd apps/web_client
    flutter build apk --release --dart-define=SIGNALING_URL="$SIGNALING_URL"
  )
fi

if [[ ! -f "$SRC_APK" ]]; then
  echo "✖ ບໍ່ພົບ $SRC_APK — ລອງ build ກ່ອນ (ຫຼືຢ່າໃສ່ SKIP_BUILD=1)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp "$SRC_APK" "$OUT_APK"
echo "✔ ສຳເລັດ: $OUT_APK"
ls -lh "$OUT_APK"
