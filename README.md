# 🟠 ໂຍນໄຟລ໌ (YonFile)

> **ຄຳຂວັນ:** *"ເປີດເວັບ ເຫັນກັນ ໂຍນໄຟລ໌ທັນທີ — ປອດໄພ ໄວແຮງ ບໍ່ຕ້ອງລົງແອັບ"*

**ໂຍນໄຟລ໌ (YonFile)** ແມ່ນລະບົບສົ່ງໄຟລ໌ ແລະ ຂໍ້ຄວາມລະຫວ່າງອຸປະກອນ
(Cross-Platform) ທີ່ເຮັດວຽກໄດ້ທັງ **LAN ດຽວກັນ** ແລະ **ຂ້າມເຄືອຂ່າຍ (4G/5G)**.
ໄຟລ໌ຖືກສົ່ງແບບ **Peer-to-Peer** ຜ່ານ WebRTC DataChannel (ເຂົ້າລະຫັດ End-to-End
ດ້ວຍ DTLS) — server **ບໍ່ເກັບໄຟລ໌** (Zero-Storage) ເຮັດໜ້າທີ່ພຽງ signaling ແລະ ເສີບ web client.

---

## ສາລະບານ

1. [ຄວາມສາມາດຫຼັກ (Feature Spec)](#1-ຄວາມສາມາດຫຼັກ-feature-spec)
2. [ການຄົ້ນຫາ ແລະ ຈັບຄູ່ອຸປະກອນ](#2-ການຄົ້ນຫາ-ແລະ-ຈັບຄູ່ອຸປະກອນ)
3. [ໂປຣໂຕຄໍການໂຍນໄຟລ໌](#3-ໂປຣໂຕຄໍການໂຍນໄຟລ໌)
4. [ຄວາມປອດໄພ](#4-ຄວາມປອດໄພ)
5. [UX/UI & Design System](#5-uxui--design-system)
6. [ສະຖາປັດຕະຍະກຳ & ໂປຣໂຕຄໍ Server](#6-ສະຖາປັດຕະຍະກຳ--ໂປຣໂຕຄໍ-server)
7. [ໂຄງສ້າງ Monorepo](#7-ໂຄງສ້າງ-monorepo)
8. [ເທັກໂນໂລຍີທີ່ໃຊ້](#8-ເທັກໂນໂລຍີທີ່ໃຊ້)
9. [ການພັດທະນາ ແລະ ການທົດສອບ](#9-ການພັດທະນາ-ແລະ-ການທົດສອບ)
10. [Build & Deploy](#10-build--deploy)
11. [STUN / TURN](#11-stun--turn)
12. [ແພລດຟອມທີ່ຮອງຮັບ](#12-ແພລດຟອມທີ່ຮອງຮັບ)
13. [ຂີດຈຳກັດທີ່ຮູ້](#13-ຂີດຈຳກັດທີ່ຮູ້)
14. [Roadmap](#14-roadmap)

---

## 1. ຄວາມສາມາດຫຼັກ (Feature Spec)

| # | ຄວາມສາມາດ | ລາຍລະອຽດ |
| :-- | :-- | :-- |
| 1 | **ໂຍນໄຟລ໌ P2P** | ສົ່ງໄຟລ໌ໂດຍກົງລະຫວ່າງອຸປະກອນຜ່ານ `RTCDataChannel` ບໍ່ຜ່ານ server |
| 2 | **ຂໍ້ຄວາມ** | ສົ່ງຂໍ້ຄວາມສັ້ນຜ່ານ DataChannel ດຽວກັນ (JSON `text`) |
| 3 | **ຄົ້ນຫາ LAN ອັດຕະໂນມັດ** | ອຸປະກອນທີ່ມີ Public IP ດຽວກັນເຫັນກັນອັດຕະໂນມັດ |
| 4 | **ຈັບຄູ່ຂ້າມເຄືອຂ່າຍ** | ລະຫັດຫ້ອງ PIN 6 ຕົວເລກ ຫຼື QR Code |
| 5 | **ຫຼາຍໄຟລ໌** | ເລືອກຫຼາຍໄຟລ໌ໃນຄັ້ງດຽວ ສົ່ງແບບລຳດັບ |
| 6 | **ກວດສອບ SHA-256** | ກວດຄວາມຖືກຕ້ອງຂອງຂໍ້ມູນທັງສອງຝັ່ງ |
| 7 | **ຄວາມຄືບໜ້າ + ຄວາມໄວ** | ແຖບເປີເຊັນ, ຄວາມໄວ MB/s, ຂະໜາດ / ສະຖານະ |
| 8 | **ຍອມຮັບ / ປະຕິເສດ** | ຜູ້ຮັບຢືນຢັນກ່ອນໄຟລ໌ເລິ່ມສົ່ງ |
| 9 | **ຍົກເລີກໄດ້** | ຍົກເລີກກາງທາງ ທັງສອງຝັ່ງ |
| 10 | **Drag & Drop** | ລາກໄຟລ໌ຈາກ OS ມາວາງ ຫຼື ວາງໃສ່ avatar ອຸປະກອນ |
| 11 | **Radar View** | ວົງເຣດາສີສົ້ມແບບ Animation ສະແດງອຸປະກອນອ້ອມຕົວ |
| 12 | **Responsive** | Layout ປ່ຽນຕາມຂະໜາດໜ້າຈໍ (ມືຖື / ແທັບເລັດ / ຄອມ) |
| 13 | **Dark / Light** | ໂໝດມືດ (ຄ່າເລີ່ມຕົ້ນ) ແລະ ແຈ້ງ ຈື່ຄ່າໄວ້ |
| 14 | **PWA** | ຕິດຕັ້ງລົງໜ້າຈໍມືຖື/ຄອມໄດ້ |
| 15 | **ປອດໄພ** | DTLS E2E, Zero-Storage, ຈຳກັດຂະໜາດ, ປ້ອງກັນ IP/PIN |

### ລາຍລະອຽດການສົ່ງໄຟລ໌
- **Chunk:** ຕັດໄຟລ໌ອອກເປັນຕ່ອນລະ **64 KB** (`65,536 bytes`).
- **Backpressure:** ກ່ອນສົ່ງແຕ່ລະ chunk ຈະກວດ `bufferedAmount`; ຖ້າເກີນ **1 MB** ຈະລໍຖ້າ
  (poll ທຸກ 20ms) ຈົນ buffer ຫຼຸດລົງ ເພື່ອບໍ່ໃຫ້ browser/ອຸປະກອນ ຄ້າງ.
- **ກວດສອບ:** ສົ່ງ SHA-256 ຕອນ `eof`; ປາຍທາງກວດທັງ **ຂະໜາດ** ແລະ **SHA-256** ກ່ອນ
  ບັນທຶກ ແລະ ຕອບກັບ `transfer-complete`.
- **ຂີດຈຳກັດ:** ຂະໜາດລວມຕໍ່ການສົ່ງ/ຮັບ ສູງສຸດ **512 MB** (ຈຳກັດ memory).

---

## 2. ການຄົ້ນຫາ ແລະ ຈັບຄູ່ອຸປະກອນ

**ໂໝດ LAN ດຽວກັນ (Zero-Config):** ອຸປະກອນທີ່ເຂົ້າ Signaling ຈະຖືກຈັດກຸ່ມຕາມ
**Public IP** ທີ່ server ເຫັນ (ຮອງຮັບ `CF-Connecting-IP`, `X-Real-IP`,
`X-Forwarded-For`). ອຸປະກອນທີ່ຢູ່ວົງດຽວກັນຈະເຫັນກັນໃນໜ້າ Radar ອັດຕະໂນມັດ.
ເມື່ອໂຍນ → WebRTC ICE ຈະເລືອກ `host candidate` (Local→Local) ເຮັດໃຫ້ຂໍ້ມູນແລ່ນຜ່ານ
Router ພາຍໃນ ບໍ່ເປືອງອິນເຕີເນັດພາຍນອກ.

**ໂໝດຂ້າມເຄືອຂ່າຍ (PIN / QR):**
- ອຸປະກອນສ້າງ **PIN 6 ຕົວເລກ** ອັດຕະໂນມັດ ແລະ ເຂົ້າຫ້ອງຂອງຕົນເອງ (ສະແດງເປັນ `849-201`).
- ອີກເຄື່ອງສະແກນ **QR** (`yonfile:<pin>`) ຫຼື ພິມ PIN ເຂົ້າຫ້ອງດຽວກັນ.
- ກົດ “ອອກ” ຈະສ້າງ PIN ໃໝ່; ຫຼັງ reconnect ຈະ join ຄືນອັດຕະໂນມັດ.
- ໃຊ້ **STUN** ທະລຸ NAT ແລະ **TURN (Coturn)** ເປັນຕົວສຳຮອງ (Symmetric NAT).

> **ໝາຍເຫດ:** ການຈັດກຸ່ມ LAN ອີງໃສ່ Public IP ຈຶ່ງບໍ່ຢືນຢັນ LAN ດຽວກັນ 100% —
> ເຄືອຂ່າຍຕ່າງບ່ອນອາດມີ IP ຮ່ວມ, ຫຼື LAN ດຽວກັນອາດອອກ proxy ຄົນລະທາງ (ໃຊ້ PIN ແທນ).

---

## 3. ໂປຣໂຕຄໍການໂຍນໄຟລ໌

```text
[Sender]                                                    [Receiver]
   |--- 1. JSON {"type":"offer-file","id","name","size","mime"} ---->|
   |<-- 2. JSON {"type":"accept-file","id"}  ຫຼື "reject-file" -------|
   |--- 3. Binary Chunk #1 (64 KB) --------------------------------->|
   |--- 4. Binary Chunk #2 (64 KB) --------------------------------->|
   |    ... (ກວດ bufferedAmount < 1 MB ຕະຫຼອດເວລາ) ...                |
   |--- 5. JSON {"type":"eof","id","sha256"} ----------------------->|
   |<-- 6. JSON {"type":"transfer-complete","id","verified"} --------|
```

| ຂໍ້ຄວາມ | ທິດທາງ | ໜ້າທີ່ |
| :-- | :-- | :-- |
| `offer-file` | Sender → Receiver | ສະເໜີສົ່ງໄຟລ໌ (id, name, size, mime) |
| `accept-file` | Receiver → Sender | ຍອມຮັບ |
| `reject-file` | Receiver → Sender | ປະຕິເສດ / ໄຟລ໌ໃຫຍ່ເກີນ / ຊ່ອງບໍ່ຫວ່າງ |
| *(binary)* | Sender → Receiver | ຕ່ອນຂໍ້ມູນ 64 KB |
| `eof` | Sender → Receiver | ສິ້ນສຸດ + SHA-256 |
| `transfer-complete` | Receiver → Sender | ຜົນກວດສອບ |
| `cancel-file` | ທັງສອງ | ຍົກເລີກ |
| `text` | ທັງສອງ | ຂໍ້ຄວາມ |

---

## 4. ຄວາມປອດໄພ

- **End-to-End Encryption** — WebRTC ບັງຄັບ **DTLS** ໃນທຸກ `RTCDataChannel`
  (server ອ່ານຂໍ້ມູນບໍ່ໄດ້).
- **Zero-Storage Server** — server ບໍ່ເກັບໄຟລ໌/ຂໍ້ຄວາມ ເຮັດພຽງ routing signaling.
- **Signal Scoping** — relay signaling ໄດ້ສະເພາະອຸປະກອນ **IP ດຽວກັນ** ຫຼື **ຫ້ອງ PIN ດຽວກັນ**.
- **ຈຳກັດຂະໜາດ message** — ປະຕິເສດ message ເກີນ **256 KB** (close 1009).
- **PIN Rate Limit** — ຈຳກັດ **20 ຄັ້ງ / 60 ວິນາທີ / IP** ແລະ ກວດຮູບແບບ `^\\d{6}$`.
- **ກວດຂໍ້ມູນຝັ່ງຮັບ** — ກວດຂະໜາດບໍ່ໃຫ້ເກີນທີ່ແຈ້ງ, ກວດ SHA-256, ກວດ length ຕອນ `eof`.
- **ເຮັດຄວາມສະອາດຊື່ໄຟລ໌** — ລຶບ `\\ /` ແລະ control characters ກ່ອນບັນທຶກ.
- **TURN ບໍ່ຝັງ secret** — ໃຊ້ Coturn REST credentials ອາຍຸ 10 ນາທີ ຈາກ `/api/ice-servers`.

---

## 5. UX/UI & Design System

### ໂທນສີ (Modern Vibrant Orange)
| ໝວດ | Token | Hex | ການໃຊ້ |
| :-- | :-- | :-- | :-- |
| Primary | `YonOrange` | `#FF6B00` | ປຸ່ມ, ວົງເຣດາ, ໄອຄອນ active, ຂອບ dropzone |
| Gradient | `YonGradient` | `#FF9E00` ➔ `#FF5500` | Progress bar, ປຸ່ມ CTA |
| Dark BG | `SlateDark` | `#0F172A` | ພື້ນຫຼັງໂໝດມືດ |
| Dark Surface | `SlateCard` | `#1E293B` | ກ່ອງຂໍ້ມູນ |
| Light BG | `CleanLight` | `#F8FAFC` | ພື້ນຫຼັງໂໝດແຈ້ງ |
| Success | `EmeraldGreen` | `#10B981` | ສຳເລັດ / ອອນລາຍ |
| Warning | `AmberGold` | `#F59E0B` | ກຳລັງຈັບຄູ່ / ລໍຖ້າ |
| Error | `RoseRed` | `#EF4444` | ລົ້ມເຫຼວ / ຍົກເລີກ |

### Typography
- **ພາສາລາວ:** `Noto Sans Lao Looped` — **bundle ໄວ້ໃນແອັບ** (400/600/700) ເພື່ອໃຫ້
  ຂໍ້ຄວາມລາວສະແດງຄົບໃນ renderer **WASM/Skwasm** ທີ່ບໍ່ມີ system-font fallback.
- **ອັງກິດ/ຕົວເລກ:** `Inter` + `tabular-nums` ເພື່ອບໍ່ໃຫ້ຕົວເລກຄວາມໄວສັ່ນ.

### Breakpoints
- **ມືຖື `< 600px`** — Column: TopBar → ຊື່ເຄື່ອງ → Radar → ປຸ່ມ PIN / ປະຫວັດ.
- **ແທັບເລັດ / ຄອມ `>= 600px`** — Row: ຊ້າຍ Radar + Dropzone, ຂວາ ກ່ອງ PIN/QR + ສະຖານະໂຍນໄຟລ໌.

---

## 6. ສະຖາປັດຕະຍະກຳ & ໂປຣໂຕຄໍ Server

```text
+------------------------ COOLIFY / DOCKER ------------------------+
|  Node.js Server (:3000)                                          |
|   ├── Static  --->  ເສີບ Flutter Web (PWA/WASM)                    |
|   ├── WS /ws   --->  Signaling (ຈັບຄູ່ LAN IP & PIN Room)          |
|   └── /api/ice-servers --->  STUN/TURN credentials               |
+--------------------------------+---------------------------------+
                                 | WSS
        +------------------------+------------------------+
        v                                                 v
  ອຸປະກອນທີ 1  <=========== WebRTC DataChannel ===========>  ອຸປະກອນທີ 2
              (DTLS 1.x Encrypted · LAN ຜ່ານ Router / WAN ຜ່ານ TURN)
```

### HTTP Endpoints
| Method | Path | ຄຳອະທິບາຍ |
| :-- | :-- | :-- |
| `GET` | `/health` | `{ "status": "ok", "activePeers": n }` (ສຳລັບ Coolify healthcheck) |
| `GET` | `/api/ice-servers` | ຄືນ STUN + TURN; ຖ້າຕັ້ງ TURN ຈະອອກ credentials ອາຍຸ 10 ນາທີ |
| `GET` | `/*` | ເສີບ Flutter Web ທີ່ build ແລ້ວ (SPA fallback → `index.html`) |

### WebSocket `/ws`
| ໄປຫາ Server | ຄຳອະທິບາຍ |
| :-- | :-- |
| `register` | ລົງທະບຽນ (name, deviceType) |
| `update-name` | ປ່ຽນຊື່ອຸປະກອນ |
| `join-pin` / `leave-pin` | ເຂົ້າ / ອອກຫ້ອງ PIN |
| `signal` | ສົ່ງຕໍ່ offer/answer/ICE ໄປຫາ `targetId` |

| ຈາກ Server | ຄຳອະທິບາຍ |
| :-- | :-- |
| `registered` | ຄືນ `peerId` + `ip` |
| `peers-updated` | ລາຍຊື່ອຸປະກອນ (`scope: lan` ຫຼື `pin`) |
| `signal` | relay ພ້ອມ `senderId` / `senderName` |
| `error` | `invalid_pin` / `pin_rate_limited` |

---

## 7. ໂຄງສ້າງ Monorepo

```text
yonfile/
├── package.json                  # Root scripts
├── pnpm-workspace.yaml
├── Dockerfile                    # Multi-stage: Flutter → Node → Production
├── docker-compose.yml            # yonfile + coturn (profile: turn)
├── .env.example
├── apps/
│   ├── server/                   # Node.js + Express + ws (Signaling & Static)
│   │   ├── src/{index,roomManager,types}.ts
│   │   └── test/signaling.test.ts
│   └── web_client/               # Flutter (Web, Android, iOS, Desktop)
│       ├── assets/fonts/         # Noto Sans Lao Looped
│       ├── web/{index.html,manifest.json}
│       └── lib/
│           ├── main.dart
│           ├── core/{theme,constants}
│           ├── models/{peer_device,file_transfer_state,picked_file}
│           ├── services/{signaling,webrtc,file_chunker}_service.dart
│           └── ui/screens/home_screen.dart + ui/widgets/*
```

---

## 8. ເທັກໂນໂລຍີທີ່ໃຊ້

**Backend:** Node.js ≥20, TypeScript 5.5, Express 4, `ws` 8, `tsx`.

**Frontend:** Flutter 3.38 / Dart 3.10 —
`flutter_webrtc`, `web_socket_channel`, `file_picker`, `desktop_drop`, `qr_flutter`,
`mobile_scanner`, `crypto`, `google_fonts`, `shared_preferences`, `http`.

**Infra:** pnpm workspace, Docker multi-stage, Coturn, Coolify-ready.

---

## 9. ການພັດທະນາ ແລະ ການທົດສອບ

```bash
pnpm install

# Signaling server ທີ່ http://localhost:3000
pnpm dev:server

# Flutter web ທີ່ http://localhost:8080 (dev ຈະຊີ້ server :3000 ອັດຕະໂນມັດ)
cd apps/web_client
flutter pub get
flutter run -d chrome --web-port 8080 \
  --dart-define=SIGNALING_URL=ws://localhost:3000/ws
```

**Tests & Lint:**
```bash
pnpm test:server     # 9 tests (node:test + tsx)
pnpm analyze:web     # flutter analyze
pnpm test:web        # 6 tests (chunking + SHA-256)
```

---

## 10. Build & Deploy

```bash
pnpm build:server    # tsc → apps/server/dist
pnpm build:web       # flutter build web --release --wasm
docker build -t yonfile .
docker compose up -d --build
```

### Build ແອັບ Native (APK / macOS)

**ສຳຄັນ:** native build **ຕ້ອງ** ກຳນົດ `SIGNALING_URL` ຕອນ build (ບໍ່ຄື web ທີ່ auto ໃຊ້ origin):
```bash
SIGNALING_URL=wss://your-domain/ws pnpm build:apk       # → app-release.apk
SIGNALING_URL=wss://your-domain/ws pnpm build:appbundle # → Play Store .aab
SIGNALING_URL=wss://your-domain/ws pnpm build:macos     # → .app
```
ຖ້າບໍ່ກຳນົດ ຈະໃຊ້ຄ່າ default `wss://yonfile.example/ws` (ໃຊ້ໄດ້ແຕ່ຕ້ອງແກ້). ແອັບຈະ**ຕໍ່ server ບໍ່ໄດ້**ຖ້າ
URL ຜິດ. ການຕັ້ງຄ່າ platform ທີ່ກ່ຽວຂ້ອງໄດ້ເຮັດໃຫ້ແລ້ວ:
- **Android:** `INTERNET` + `ACCESS_NETWORK_STATE` permission, `network_security_config`
  (ອະນຸຍາດ cleartext `ws://` ສຳລັບ server LAN), ຊື່ແອັບ “ໂຍນໄຟລ໌”.
- **macOS:** entitlements `network.client` + `network.server` (ຈຳເປັນສຳລັບ signaling + WebRTC).
- **iOS:** `NSAppTransportSecurity` (LAN cleartext) + `NSCameraUsageDescription`.

**Coolify:** Build Pack = `Dockerfile`, Base Directory = `/`, Port = `3000`, ໃຊ້ **HTTPS**
(WebRTC ຕ້ອງການ secure context). ການ build web ໃຊ້ **WASM/Skwasm** ເພື່ອຫຼີກລ້ຽງ
ບັນຫາ CanvasKit ທີ່ສະແດງກອບສີເທົາທັບ radar ໃນ Chrome.

> 📘 ຄູ່ມືລະອຽດການ Deploy ຂຶ້ນ Coolify: **[DEPLOY_COOLIFY.md](DEPLOY_COOLIFY.md)**

---

## 11. STUN / TURN

- **STUN ເລີ່ມຕົ້ນ (ຟຣີ):** `stun:stun.l.google.com:19302` — ພຽງພໍ LAN 100% ແລະ
  ຂ້າມເນັດທົ່ວໄປ ~80%.
- **TURN (Production 100%):** ຕັ້ງ `TURN_URL`, `TURN_SHARED_SECRET`, `TURN_REALM` ໃນ `.env`
  ຕາມ [.env.example](.env.example) (secret ດຽວກັນກັບ Coturn) ແລ້ວ:
  ```bash
  docker compose --profile turn up -d
  ```
  Server ຈະອອກ **Coturn REST credentials** ອາຍຸ 10 ນາທີ ຜ່ານ `GET /api/ice-servers`
  (HMAC-SHA1) — **ຢ່າຝັງ shared secret ໃນ browser build**.
- ເປີດ UDP `3478` ແລະ relay ports `49152–65535` ຜ່ານ firewall.

---

## 12. ແພລດຟອມທີ່ຮອງຮັບ

| Platform | ສະຖານະ | Artifact |
| :-- | :-- | :-- |
| **Web (PWA)** | ✅ ສ້າງໄດ້ | `apps/web_client/build/web/` |
| **Android** | ✅ ສ້າງໄດ້ | `build/app/outputs/flutter-apk/app-release.apk` (ແອັບແທ້ ~98 MB) |
| **macOS** | ✅ ສ້າງໄດ້ | `build/macos/Build/Products/Release/yonfile_client.app` |
| **iOS** | ⛔ ຕ້ອງການ iOS platform + Apple Dev Team | `.ipa` |
| **Windows / Linux** | ⛔ ຕ້ອງ build ເທິງ OS ນັ້ນ | `.exe` / AppImage |

```bash
SIGNALING_URL=wss://your-domain/ws pnpm build:apk    # Android
SIGNALING_URL=wss://your-domain/ws pnpm build:macos  # macOS
# iOS (ຕ້ອງມີ iOS platform ໃນ Xcode + Apple Development Team):
cd apps/web_client && flutter build ios --release --no-codesign
```

---

## 13. ຂີດຈຳກັດທີ່ຮູ້

- ໄຟລ໌ຖືກໂຫຼດເຂົ້າ memory ທັງໝົດກ່ອນສົ່ງ → ຈຳກັດ **512 MB/ຄັ້ງ**.
- ການຈັດກຸ່ມ LAN ອີງ Public IP (ບໍ່ຢືນຢັນ LAN 100%) — ໃຊ້ PIN ເມື່ອບໍ່ແນ່ໃຈ.
- Signaling ເກັບ peer ໃນ memory ຢ່າງດຽວ (ຮອງຮັບ single-instance).
- ການສະແກນ QR ຕ້ອງການ ກ້ອງ + HTTPS.

---

## 14. Roadmap

- [x] Milestone 1 — Core Setup: pnpm Monorepo + Signaling Server (LAN pairing)
- [x] Milestone 2 — Flutter UI & Radar: Adaptive Layout, radar, PIN/QR
- [x] Milestone 3 — WebRTC File Chunking: 64KB, progress, SHA-256
- [x] Milestone 4 — PWA & Coolify Deployment: manifest + multi-stage Dockerfile
- [x] Milestone 5 (ບາງສ່ວນ) — Android APK + macOS app
- [ ] Milestone 5 (ຕໍ່) — iOS `.ipa` + Windows/Linux
- [ ] ທົດສອບ deployment ຈິງ + TURN ຂ້າມເຄືອຂ່າຍດ້ວຍອຸປະກອນຈິງ

---

## 15. FAQ

**ຕ້ອງມີ Signaling Server ສະເໝີບໍ?**
ແມ່ນ. ແອັບບໍ່ມີ server ຢູ່ໃນຕົວ — ອຸປະກອນຕ້ອງເຊື່ອມກັບ server ເພື່ອ**ຈັບຄູ່** ກ່ອນ.
ຫຼັງຈັບຄູ່ແລ້ວ ໄຟລ໌/ຂໍ້ຄວາມແລ່ນ P2P ໂດຍກົງ (server ບໍ່ຜ່ານໄຟລ໌, ບໍ່ເກັບຂໍ້ມູນ).
Android release ຕ້ອງ build ດ້ວຍ `SIGNALING_URL` ຊີ້ໄປຫາ server.

**ຢູ່ LAN ດຽວກັນ ຈະເຫັນກັນບໍ?**
- Server ຢູ່ອິນເຕີເນັດ (VPS) + ສອງເຄື່ອງ Wi-Fi ດຽວກັນ → ມີ Public IP ດຽວກັນ → **ເຫັນກັນອັດຕະໂນມັດ** ແລະ ໄຟລ໌ແລ່ນຜ່ານ Router ພາຍໃນ (ໄວ).
- Server ຢູ່ໃນ LAN ເອງ → ແຕ່ລະເຄື່ອງມີ Private IP ຕ່າງກັນ → **ບໍ່ auto-ເຫັນ** ຕ້ອງໃຊ້ PIN.
- ປັດຈຸບັນ ເວລາສົ່ງ ຈະ**ຖາມ PIN ຂອງຝ່າຍຮັບ** (ຄວາມປອດໄພ) ເຖິງແມ່ນຢູ່ LAN ດຽວກັນ.

**ອອກເນັດ (4G/5G) ຈະເຫັນກັນໝົດບໍ?**
ບໍ່. ແຕ່ລະເຄື່ອງມີ Public IP ຕ່າງກັນ → ຕ້ອງ **join ຫ້ອງ PIN ດຽວກັນ** (ພິມ PIN / ສະແກນ QR).
NAT ແບບ Symmetric (4G/5G ບາງຄ້າຍ) ຈຳເປັນຕ້ອງມີ **TURN**.
