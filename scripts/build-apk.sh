#!/usr/bin/env bash
# =============================================================================
# YonFile — Build Android APK → dist/YonFile.apk
#
# ການໃຊ້:
#   SIGNALING_URL=wss://your-server/ws pnpm build:apk
#
# ຕົວແປທີ່ຮັບ (env):
#   SIGNALING_URL  URL ຂອງ signaling server (default: wss://yonfile.example/ws)
#   APK_NAME       ຊື່ໄຟລ໌ APK ທີ່ຈະອອກ    (default: YonFile)
#   APK_BUILD_TYPE auto / debug / release (default: auto; no keystore = debug)
#   APK_TARGET_PLATFORM Flutter Android target platform (default: android-arm64)
#   SKIP_BUILD     1 = ໃຊ້ APK ທີ່ build ໄວ້ແລ້ວ, ບໍ່ build ໃໝ່
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SIGNALING_URL="${SIGNALING_URL:-wss://yonfile.example/ws}"
APK_NAME="${APK_NAME:-YonFile}"
SKIP_BUILD="${SKIP_BUILD:-0}"
APK_BUILD_TYPE="${APK_BUILD_TYPE:-auto}"
APK_TARGET_PLATFORM="${APK_TARGET_PLATFORM:-android-arm64}"

SIGNING_VALUES=(
  "${YONFILE_RELEASE_STORE_FILE:-}"
  "${YONFILE_RELEASE_STORE_PASSWORD:-}"
  "${YONFILE_RELEASE_KEY_ALIAS:-}"
  "${YONFILE_RELEASE_KEY_PASSWORD:-}"
)
SIGNING_COUNT=0
for value in "${SIGNING_VALUES[@]}"; do
  [[ -n "$value" ]] && ((SIGNING_COUNT += 1))
done

if [[ "$APK_BUILD_TYPE" == "auto" ]]; then
  if [[ "$SIGNING_COUNT" == "4" ]]; then
    APK_BUILD_TYPE="release"
  elif [[ "$SIGNING_COUNT" == "0" ]]; then
    APK_BUILD_TYPE="debug"
  else
    echo "✖ Android release signing is partially configured. Set all four YONFILE_RELEASE_* variables or clear them to build debug." >&2
    exit 1
  fi
fi

if [[ "$APK_BUILD_TYPE" != "debug" && "$APK_BUILD_TYPE" != "release" ]]; then
  echo "✖ APK_BUILD_TYPE must be auto, debug, or release (got: $APK_BUILD_TYPE)" >&2
  exit 1
fi
if [[ "$APK_BUILD_TYPE" == "release" && "$SIGNING_COUNT" != "4" ]]; then
  echo "✖ Release APK requires YONFILE_RELEASE_STORE_FILE, YONFILE_RELEASE_STORE_PASSWORD, YONFILE_RELEASE_KEY_ALIAS, and YONFILE_RELEASE_KEY_PASSWORD." >&2
  exit 1
fi

APK_OUTPUT_DIR="apps/web_client/build/app/outputs/flutter-apk"
SRC_APK="$APK_OUTPUT_DIR/app-arm64-v8a-${APK_BUILD_TYPE}.apk"
OUT_DIR="dist"
OUT_APK="$OUT_DIR/${APK_NAME}.apk"

if [[ "$SKIP_BUILD" != "1" ]]; then
  mkdir -p "$APK_OUTPUT_DIR"
  rm -f \
    "$APK_OUTPUT_DIR/app-armeabi-v7a-${APK_BUILD_TYPE}.apk" \
    "$APK_OUTPUT_DIR/app-arm64-v8a-${APK_BUILD_TYPE}.apk" \
    "$APK_OUTPUT_DIR/app-x86_64-${APK_BUILD_TYPE}.apk"
  echo "▶ Building Android $APK_BUILD_TYPE APK (target=$APK_TARGET_PLATFORM, SIGNALING_URL=$SIGNALING_URL)…"
  (
    cd apps/web_client
    flutter build apk "--$APK_BUILD_TYPE" --split-per-abi "--target-platform=$APK_TARGET_PLATFORM" --dart-define=SIGNALING_URL="$SIGNALING_URL"
  )
fi

if [[ ! -f "$SRC_APK" ]]; then
  echo "✖ ບໍ່ພົບ $SRC_APK — ລອງ build ກ່ອນ (ຫຼືຢ່າໃສ່ SKIP_BUILD=1)" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
cp "$SRC_APK" "$OUT_APK"
echo "✔ ສຳເລັດ: $OUT_APK"
for abi_apk in "$APK_OUTPUT_DIR"/app-*-"$APK_BUILD_TYPE".apk; do
  [[ -f "$abi_apk" ]] || continue
  [[ "$abi_apk" == "$SRC_APK" ]] && continue
  abi_name="$(basename "$abi_apk" | sed "s/^app-//; s/-${APK_BUILD_TYPE}\\.apk$//")"
  cp "$abi_apk" "$OUT_DIR/${APK_NAME}-${abi_name}.apk"
  echo "✔ ສຳເລັດ: $OUT_DIR/${APK_NAME}-${abi_name}.apk"
done
if [[ "$APK_BUILD_TYPE" == "debug" ]]; then
  echo "⚠ ໄຟລ໌ນີ້ sign ດ້ວຍ debug key ສຳລັບທົດສອບ/ຕິດຕັ້ງພາຍໃນ. ສຳລັບ release ໃຫ້ຕັ້ງ YONFILE_RELEASE_* ໃຫ້ຄົບ ຫຼືໃຊ້ APK_BUILD_TYPE=release."
fi
ls -lh "$OUT_APK"
