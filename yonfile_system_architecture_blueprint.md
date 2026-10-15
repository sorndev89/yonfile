# 🟠 ໂຍນໄຟລ໌ (YonFile) — System Architecture & UX/UI Blueprint

> **ຄຳຂວັນລະບົບ:** *"ເປີດເວັບ ເຫັນກັນ ໂຍນໄຟລ໌ທັນທີ — ປອດໄພ ໄວແຮງ ບໍ່ຕ້ອງລົງແອັບ"*  
> **ເປົ້າໝາຍ:** ລະບົບສົ່ງໄຟລ໌ ແລະ ຂໍ້ຄວາມຂ້າມອຸປະກອນ (Cross-Platform Web & Native Feel) ຜ່ານເຄືອຂ່າຍດຽວກັນ (LAN) ແລະ ຂ້າມເຄືອຂ່າຍ (WAN/4G/5G) ດ້ວຍເທັກໂນໂລຍີ WebRTC End-to-End Encryption (DTLS).

---

## 1. ພາບລວມສະຖາປັດຕະຍະກຳ (High-Level Architecture)

ລະບົບ **ໂຍນໄຟລ໌ (YonFile)** ຖືກອອກແບບໃຫ້ໃຊ້ຊັບພະຍາກອນ Server ໜ້ອຍທີ່ສຸດ (Zero-Storage Server) ໂດຍໄຟລ໌ທັງໝົດຈະຖືກສົ່ງໂດຍກົງລະຫວ່າງອຸປະກອນຫາອຸປະກອນ (Peer-to-Peer) ຜ່ານ `RTCDataChannel`.

```text
+-------------------------------------------------------------------------+
|                        COOLIFY SERVER (Docker)                          |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  | Node.js Server (Port 3000)                                        |  |
|  |  ├── HTTP Static Server  ---> ປ່ອຍໄຟລ໌ Flutter Web (PWA/Wasm)     |  |
|  |  └── WebSocket (/ws)     ---> Signaling (ຈັບຄູ່ LAN IP & PIN Room) |  |
|  +-------------------------------------------------------------------+  |
+------------------------------------+------------------------------------+
                                     |
          1. ຈັບຄູ່ອຸປະກອນ (Signaling) | (WSS Encrypted)
                                     v
+------------------------+                       +------------------------+
|   ອຸປະກອນທີ 1 (Sender)   |                       |  ອຸປະກອນທີ 2 (Receiver) |
|  iOS / Android / Web   | <===================> | Windows / Mac / Linux  |
+------------------------+   2. ໂຍນໄຟລ໌ໂດຍກົງ     +------------------------+
                             WebRTC DataChannel
                             (DTLS 1.3 Encrypted)
                             - ວົງ LAN: ຜ່ານ Wi-Fi Router ໂດຍກົງ
                             - ຂ້າມເນັດ: ຜ່ານ STUN / TURN Server
```

### ກົນໄກການເຊື່ອມຕໍ່ 2 ຮູບແບບ:
1. **ໂໝດວົງ LAN ດຽວກັນ (Zero-Config LAN Discovery):**
   * ອຸປະກອນທີ່ເຊື່ອມຕໍ່ Wi-Fi ດຽວກັນ ຈະມີ **Public IP** ດຽວກັນເມື່ອເຊື່ອມຕໍ່ເຂົ້າມາທີ່ Signaling Server.
   * Server ຈັດກຸ່ມອຸປະກອນທີ່ມີ IP ດຽວກັນໃຫ້ເຫັນກັນອັດຕະໂນມັດໃນໜ້າຈໍເຣດາ (Radar View).
   * ເມື່ອກົດໂຍນໄຟລ໌, WebRTC ICE ຈະເລືອກເສັ້ນທາງ `host candidate` (Local IP ຫາ Local IP) ເຮັດໃຫ້ຂໍ້ມູນແລ່ນຜ່ານ Router ພາຍໃນບ້ານ/ຫ້ອງການ ໂດຍບໍ່ເປືອງອິນເຕີເນັດພາຍນອກ.
2. **ໂໝດຂ້າມເຄືອຂ່າຍ (Cross-Network via PIN / QR Code):**
   * ສຳລັບກໍລະນີມືຖືໃຊ້ 4G/5G ແຕ່ຄອມພິວເຕີໃຊ້ Wi-Fi ຫ້ອງການ.
   * ຜູ້ໃຊ້ສ້າງ **ລະຫັດຫ້ອງ 6 ຕົວເລກ (PIN)** ຫຼື **ສະແກນ QR Code** ເພື່ອດຶງອຸປະກອນທັງສອງເຂົ້າສູ່ Private Room ດຽວກັນ.
   * ໃຊ້ **STUN Server** ເພື່ອทะລຸ NAT ແລະ ມີ **TURN Server (Coturn)** ເປັນຕົວສຳຮອງກໍລະນີເຄືອຂ່າຍມືຖືບລັອກ P2P (Symmetric NAT).

---

## 2. ການອອກແບບ UX/UI & Design System

### 2.1 ໂທນສີ (Modern Vibrant Orange Theme)
ອອກແບບໃຫ້ທັນສະໄໝ ໂດດເດັ່ນ ແລະ ຮອງຮັບທັງ **Dark Mode (ຄ່າເລີ່ມຕົ້ນ)** ແລະ **Light Mode**:

| ໝວດໝູ່ສີ | ຊື່ Token | ລະຫັດສີ (Hex) | ການນຳໃຊ້ |
| :--- | :--- | :--- | :--- |
| **Primary** | `YonOrange` | `#FF6B00` | ປຸ່ມຫຼັກ, ວົງເຣດາ, ໄອຄອນ Active, ຂອບ Dropzone |
| **Primary Gradient** | `YonGradient` | `#FF9E00` ➔ `#FF5500` | ແຖບສະແດງເປີເຊັນການໂຍນໄຟລ໌ (Progress Bar), ປຸ່ມ CTA |
| **Dark Background** | `SlateDark` | `#0F172A` | ພື້ນຫຼັງຫຼັກໃນໂໝດມືດ |
| **Dark Surface** | `SlateCard` | `#1E293B` (Opacity 80%) | ກ່ອງຂໍ້ມູນແບບ Glassmorphism (Blur 12px) |
| **Light Background** | `CleanLight` | `#F8FAFC` | ພື້ນຫຼັງຫຼັກໃນໂໝດແຈ້ງ |
| **Light Surface** | `PureWhite` | `#FFFFFF` | ກ່ອງຂໍ້ມູນໃນໂໝດແຈ້ງ |
| **Status: Success** | `EmeraldGreen` | `#10B981` | ໂຍນໄຟລ໌ສຳເລັດ / ອອນລາຍ |
| **Status: Warning** | `AmberGold` | `#F59E0B` | ກຳລັງຈັບຄູ່ / ລໍຖ້າການຍອມຮັບ |
| **Status: Error** | `RoseRed` | `#EF4444` | ການສົ່ງລົ້ມເຫຼວ / ຍົກເລີກ |

### 2.2 ຟອນຕົວອັກສອນ (Typography)
* **ພາສາລາວ:** `Noto Sans Lao Looped` ຫຼື `BoonBaan` (ອ່ານງ່າຍ ທັນສະໄໝ ຫົວกลมກຳລັງດີ).
* **ພາສາອັງກິດ & ຕົວເລກ:** `Inter` ຫຼື `Plus Jakarta Sans` (ໃຊ້ `tabular-nums` ສຳລັບຕົວເລກຄວາມໄວ MB/s ແລະ ເປີເຊັນ ເພື່ອບໍ່ໃຫ້ຕົວເລກສັ່ນເວລາແລ່ນ).

### 2.3 ໂຄງສ້າງໜ້າຈໍແບບ Unified Responsive Layout
ໃຊ້ໂຄ້ດ Flutter ຊຸດດຽວ ແຕ່ປັບປ່ຽນ Layout ອັດຕະໂນມັດຕາມຂະໜາດໜ້າຈໍ (`Breakpoints`):

#### 📱 1. ໜ້າຈໍມືຖື (Mobile: `< 600px`)
```text
+---------------------------------------+
| 🟠 ໂຍນໄຟລ໌ (YonFile)       [🌙] [QR]  |
| ຊື່ເຄື່ອງ: iPhone ຂອງຂ້ອຍ (ກົດປ່ຽນຊື່)  |
+---------------------------------------+
|                                       |
|             . - ~ ~ - .               |
|         . '   (( 💻 ))  ' .           |
|        /    MacBook-Pro    \          |
|       |                     |         |
|       |      (( 📱 ))       |         |
|       |       ຕົວທ່ານ        |         |
|        \                   /          |
|         ' .  (( 📱 ))  . '            |
|             ' - _ _ - '               |
|            Galaxy-S24                 |
|                                       |
|   * ແຕະໃສ່ອຸປະກອນເພື່ອເລືອກໄຟລ໌ໂຍນ *   |
+---------------------------------------+
| [ 🔗 ໃສ່ລະຫັດຂ້າມເນັດ ]  [ 📂 ປະຫວັດ ]  |
+---------------------------------------+
```

#### 💻 2. ໜ້າຈໍແທັບເລັດ ແລະ ຄອມພິວເຕີ (Tablet & Desktop: `>= 600px`)
```text
+-----------------------------------------------------------------------------------+
| 🟠 ໂຍນໄຟລ໌ (YonFile)        [ສະຖານະ: ພ້ອມໂຍນໄຟລ໌]           [🌙 ໂໝດມືດ] [ℹ️ ກ່ຽວກັບ] |
+---------------------------------------------------------+-------------------------+
|                                                         | 🔗 ໂຍນຂ້າມເຄືອຂ່າຍ (PIN)  |
|                      . - ~ ~ - .                        | +---------------------+ |
|                  . '  (( 📱 ))   ' .                    | | ລະຫັດຫ້ອງຂອງທ່ານ:     | |
|                 /   iPhone-Lao      \                   | |   [ 8 4 9 - 2 0 1 ] | |
|                |                     |                  | |   [ ສະແກນ QR Code ] | |
|                |      (( 💻 ))       |                  | | ຫຼື ໃສ່ລະຫັດເຄື່ອງອື່ນ:   | |
|                |   "PC ຂອງສົມຊາຍ"    |                  | | [______] [ເຊື່ອມຕໍ່]  | |
|                 \                   /                   | +---------------------+ |
|                  ' .             . '                    |                         |
|                      ' - _ _ - '                        | 📊 ສະຖານະການໂຍນໄຟລ໌     |
|                                                         | +---------------------+ |
|   +-------------------------------------------------+   | | 📄 ບົດລາຍງານ.pdf    | |
|   | 📥 ລາກໄຟລ໌ມາວາງໃສ່ບ່ອນນີ້ (Drag & Drop)           |   | | [████████░░] 82%    | |
|   |    ຫຼື ກົດໃສ່ຊື່ອຸປະກອນເພື່ອໂຍນໄຟລ໌ / ຂໍ້ຄວາມ        |   | | ⚡ 14.5 MB/s        | |
|   +-------------------------------------------------+   | +---------------------+ |
+---------------------------------------------------------+-------------------------+
```

---

## 3. ໂຄງສ້າງໂປຣເຈັກ Monorepo (`pnpm`)

ຈັດການທັງ Backend ແລະ Frontend ຢູ່ໃນ Git Repository ດຽວກັນ ເພື່ອຄວາມສະດວກໃນການພັດທະນາ ແລະ ການ Deploy ຜ່ານ Coolify:

```text
yonfile-monorepo/
├── package.json                  # Root scripts ສຳລັບຄວບຄຸມທັງລະບົບ
├── pnpm-workspace.yaml           # ກຳນົດขอบເຂດຂອງ pnpm workspace
├── Dockerfile                    # Multi-stage Dockerfile ສຳລັບ Coolify
├── .dockerignore                 # ຍົກເວັ້ນໄຟລ໌ບໍ່ຈຳເປັນຕອນ Build Docker
├── README.md
│
├── apps/
│   ├── server/                   # Node.js + Express + ws (Signaling & Static Host)
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   └── src/
│   │       ├── index.ts          # Entry point ຫຼັກຂອງ Server
│   │       ├── roomManager.ts    # ຈັດການກຸ່ມ LAN IP ແລະ ຫ້ອງລະຫັດ PIN 6 ຕົວເລກ
│   │       └── types.ts          # ໂຄງສ້າງຂໍ້ມູນ WebSocket Payload
│   │
│   └── web_client/               # Flutter Application (Web, Android, iOS, Desktop)
│       ├── pubspec.yaml          # Dependencies ຂອງ Flutter
│       ├── web/
│       │   ├── index.html        # ໜ້າ HTML ຫຼັກ + Loading Spinner ສີສົ້ມ
│       │   └── manifest.json     # ຕັ້ງຄ່າ PWA (ຕິດຕັ້ງລົງໜ້າຈໍມືຖື/ຄອມໄດ້)
│       └── lib/
│           ├── main.dart
│           ├── core/
│           │   ├── theme/
│           │   │   └── yon_theme.dart         # ຕັ້ງຄ່າສີສົ້ມ #FF6B00 ແລະ Dark/Light Mode
│           │   └── constants/
│           │       └── app_config.dart        # ຄ່າຄົງທີ່ (Chunk 64KB, STUN/TURN URLs)
│           ├── models/
│           │   ├── peer_device.dart           # Model ອຸປະກອນປາຍທາງ
│           │   └── file_transfer_state.dart   # Model ສະຖານະການສົ່ງໄຟລ໌
│           ├── services/
│           │   ├── signaling_service.dart     # WebSocket Client ລົມກັບ Node.js
│           │   ├── webrtc_service.dart        # ຈັດການ RTCPeerConnection & DataChannel
│           │   └── file_chunker_service.dart  # ຕັດໄຟລ໌ເປັນຕ່ອນ 64KB + ກວດ SHA-256
│           └── ui/
│               ├── screens/
│               │   └── home_screen.dart       # ໜ້າຈໍຫຼັກ Adaptive (Mobile/Desktop)
│               └── widgets/
│                   ├── radar_canvas.dart      # ວົງເຣດາສີສົ້ມ CustomPaint Animation
│                   ├── peer_avatar.dart       # ປຸ່ມອຸປະກອນປາຍທາງ + DragTarget
│                   ├── pin_room_card.dart     # ກ່ອງລະຫັດ PIN 6 ຕົວເລກ & QR Code
│                   └── transfer_sheet.dart    # Modal ສະແດງຄວາມຄືບໜ້າການໂຍນໄຟລ໌
```

---

## 4. ລາຍລະອຽດໂຄ້ດຕັ້ງຕົ້ນຂອງລະບົບ (Core Implementation Blueprints)

### 4.1 ໄຟລ໌ຕັ້ງຄ່າ Root Monorepo

#### `pnpm-workspace.yaml`
```yaml
packages:
  - 'apps/*'
```

#### `package.json` (Root)
```json
{
  "name": "yonfile-monorepo",
  "version": "1.0.0",
  "private": true,
  "description": "ໂຍນໄຟລ໌ (YonFile) - Cross-platform P2P File Transfer",
  "scripts": {
    "dev:server": "pnpm --filter @yonfile/server dev",
    "build:server": "pnpm --filter @yonfile/server build",
    "start:server": "pnpm --filter @yonfile/server start",
    "dev:web": "cd apps/web_client && flutter run -d chrome --web-port 8080",
    "build:web": "cd apps/web_client && flutter build web --release"
  },
  "engines": {
    "node": ">=20.0.0",
    "pnpm": ">=9.0.0"
  }
}
```

---

### 4.2 Signaling Server (`apps/server`)

#### `apps/server/package.json`
```json
{
  "name": "@yonfile/server",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "express": "^4.19.2",
    "ws": "^8.18.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.0",
    "@types/ws": "^8.5.12",
    "tsx": "^4.15.0",
    "typescript": "^5.5.0"
  }
}
```

#### `apps/server/tsconfig.json`
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "CommonJS",
    "rootDir": "./src",
    "outDir": "./dist",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
```

#### `apps/server/src/index.ts`
```typescript
import express from 'express';
import http from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import path from 'path';
import crypto from 'crypto';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

interface Peer {
  id: string;
  name: string;
  deviceType: 'mobile' | 'tablet' | 'desktop';
  ip: string;
  pinRoom: string | null;
  ws: WebSocket;
}

const peers = new Map<string, Peer>();

// ດຶງ Public IP ແທ້ຈາກ Reverse Proxy (Coolify / Traefik / Cloudflare)
function extractClientIp(req: http.IncomingMessage): string {
  const cfIp = req.headers['cf-connecting-ip'];
  const xRealIp = req.headers['x-real-ip'];
  const xForwardedFor = req.headers['x-forwarded-for'];

  if (typeof cfIp === 'string') return cfIp.trim();
  if (typeof xRealIp === 'string') return xRealIp.trim();
  if (typeof xForwardedFor === 'string') return xForwardedFor.split(',')[0].trim();
  return req.socket.remoteAddress || '127.0.0.1';
}

wss.on('connection', (ws, req) => {
  const peerId = crypto.randomUUID();
  const clientIp = extractClientIp(req);

  ws.on('message', (rawMessage) => {
    try {
      const msg = JSON.parse(rawMessage.toString());

      switch (msg.type) {
        // 1. ລົງທະບຽນອຸປະກອນເມື່ອເປີດເວັບ
        case 'register': {
          peers.set(peerId, {
            id: peerId,
            name: msg.name || 'ອຸປະກອນ YonFile',
            deviceType: msg.deviceType || 'desktop',
            ip: clientIp,
            pinRoom: null,
            ws,
          });
          ws.send(JSON.stringify({ type: 'registered', peerId, ip: clientIp }));
          notifySameLanPeers(clientIp);
          break;
        }

        // 2. ປ່ຽນຊື່ອຸປະກອນ
        case 'update-name': {
          const peer = peers.get(peerId);
          if (peer && msg.name) {
            peer.name = msg.name;
            notifySameLanPeers(peer.ip);
            if (peer.pinRoom) notifySamePinRoomPeers(peer.pinRoom);
          }
          break;
        }

        // 3. ເຂົ້າຮ່ວມຫ້ອງ PIN 6 ຕົວເລກ (ສຳລັບໂຍນຂ້າມ Network)
        case 'join-pin': {
          const peer = peers.get(peerId);
          if (peer && msg.pin) {
            const oldPin = peer.pinRoom;
            peer.pinRoom = String(msg.pin).trim();
            if (oldPin) notifySamePinRoomPeers(oldPin);
            notifySamePinRoomPeers(peer.pinRoom);
          }
          break;
        }

        // 4. ສົ່ງຕໍ່ WebRTC Signaling (Offer, Answer, ICE Candidate, ຄຳຂໍໂຍນໄຟລ໌)
        case 'signal': {
          const targetPeer = peers.get(msg.targetId);
          const senderPeer = peers.get(peerId);
          if (targetPeer && targetPeer.ws.readyState === WebSocket.OPEN && senderPeer) {
            targetPeer.ws.send(
              JSON.stringify({
                type: 'signal',
                senderId: peerId,
                senderName: senderPeer.name,
                payload: msg.payload,
              })
            );
          }
          break;
        }
      }
    } catch (err) {
      console.error('Invalid WS message:', err);
    }
  });

  ws.on('close', () => {
    const peer = peers.get(peerId);
    peers.delete(peerId);
    if (peer) {
      notifySameLanPeers(peer.ip);
      if (peer.pinRoom) notifySamePinRoomPeers(peer.pinRoom);
    }
  });
});

function notifySameLanPeers(ip: string) {
  const group = Array.from(peers.values()).filter((p) => p.ip === ip);
  const serialized = group.map(({ id, name, deviceType }) => ({ id, name, deviceType, scope: 'lan' }));
  group.forEach((member) => {
    if (member.ws.readyState === WebSocket.OPEN) {
      member.ws.send(JSON.stringify({ type: 'peers-updated', scope: 'lan', peers: serialized }));
    }
  });
}

function notifySamePinRoomPeers(pin: string) {
  const group = Array.from(peers.values()).filter((p) => p.pinRoom === pin);
  const serialized = group.map(({ id, name, deviceType }) => ({ id, name, deviceType, scope: 'pin' }));
  group.forEach((member) => {
    if (member.ws.readyState === WebSocket.OPEN) {
      member.ws.send(JSON.stringify({ type: 'peers-updated', scope: 'pin', pin, peers: serialized }));
    }
  });
}

// Healthcheck Endpoint ສຳລັບ Coolify
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', activePeers: peers.size });
});

// ເຊີບໄຟລ໌ Flutter Web ທີ່ Build ແລ້ວ
const flutterWebDir = path.join(__dirname, '../../web_client/build/web');
app.use(express.static(flutterWebDir));
app.get('*', (_req, res) => {
  res.sendFile(path.join(flutterWebDir, 'index.html'));
});

const PORT = Number(process.env.PORT) || 3000;
server.listen(PORT, '0.0.0.0', () => {
  console.log(`🟠 YonFile Server is running on http://0.0.0.0:${PORT}`);
});
```

---

### 4.3 Flutter Web Client & Protocol ການໂຍນໄຟລ໌ (`apps/web_client`)

#### 1. ແພັກເກັດທີ່ຈຳເປັນໃນ `pubspec.yaml`
```yaml
name: yonfile_client
description: ໂຍນໄຟລ໌ (YonFile) - Fast & Secure Cross-Device File Transfer
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_webrtc: ^0.11.7       # ຫົວໃຈຫຼັກສຳລັບ P2P WebRTC DataChannel
  web_socket_channel: ^3.0.1    # ເຊື່ອມຕໍ່ Signaling Server
  file_picker: ^8.1.2           # ເລືອກໄຟລ໌ທຸກປະເພດຈາກມືຖື/ຄອມ
  desktop_drop: ^0.4.4          # ຮອງຮັບ Drag & Drop ໄຟລ໌ເທິງເວັບ ແລະ Desktop
  qr_flutter: ^4.1.0            # ສ້າງ QR Code ສຳລັບຫ້ອງ PIN
  mobile_scanner: ^5.2.3        # ສະແກນ QR Code ຜ່ານກ້ອງມືຖື
  crypto: ^3.0.5                # ກວດສອບຄວາມຖືກຕ້ອງຂອງໄຟລ໌ດ້ວຍ SHA-256
  google_fonts: ^6.2.1          # ຟອນ Noto Sans Lao Looped & Inter
  shared_preferences: ^2.3.2    # ຈື່ຊື່ອຸປະກອນ ແລະ ໂໝດສີມືດ/ແຈ້ງ
```

#### 2. ການຕັ້ງຄ່າ Theme ສີສົ້ມ (`lib/core/theme/yon_theme.dart`)
```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class YonTheme {
  static const Color yonOrange = Color(0xFFFF6B00);
  static const Color yonOrangeLight = Color(0xFFFF9E00);
  static const Color slateDarkBg = Color(0xFF0F172A);
  static const Color slateDarkCard = Color(0xFF1E293B);
  static const Color lightBg = Color(0xFFF8FAFC);

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: slateDarkBg,
    colorScheme: const ColorScheme.dark(
      primary: yonOrange,
      secondary: yonOrangeLight,
      surface: slateDarkCard,
    ),
    textTheme: GoogleFonts.notoSansLaoLoopedTextTheme(ThemeData.dark().textTheme),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: yonOrange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    colorScheme: const ColorScheme.light(
      primary: yonOrange,
      secondary: yonOrangeLight,
      surface: Colors.white,
    ),
    textTheme: GoogleFonts.notoSansLaoLoopedTextTheme(ThemeData.light().textTheme),
  );
}
```

#### 3. ໂປຣໂຕຄໍການຕັດໄຟລ໌ ແລະ ການເຂົ້າລະຫັດ (`lib/services/file_chunker_service.dart`)
ເພື່ອປ້ອງກັນບັນຫາ Browser ຄ້າງເວລາໂຍນໄຟລ໌ຂະໜາດໃຫຍ່ ແລະ ຮັບປະກັນຄວາມປອດໄພ:

* **ມາດຕະຖານຄວາມປອດໄພ:** WebRTC ບັງຄັບໃຊ້ **DTLS 1.3 (Datagram Transport Layer Security)** ທຸກຄັ້ງທີ່ສ້າງ `RTCDataChannel` ເຊິ່ງເຂົ້າລະຫັດແບບ End-to-End ໂດຍອັດຕະໂນມັດ.
* **ຂະໜາດ Chunk:** ຕັດໄຟລ໌ອອກເປັນຕ່ອນລະ **64 KB ($65,536\text{ bytes}$)**.
* **ການຄວບຄຸມ Backpressure:** ກ່ອນສົ່ງແຕ່ລະ Chunk ຈະກວດເບິ່ງຄ່າ `dataChannel.bufferedAmount` ຖ້າສູງກວ່າ $1\text{ MB}$ ($1,048,576\text{ bytes}$) ຈະລໍຖ້າໃຫ້ Buffer ວ່າງກ່ອນ ຈຶ່ງສົ່ງຕ່ອນຕໍ່ໄປ.

```text
[Sender]                                                    [Receiver]
   |--- 1. JSON: {"type":"offer-file", "name":"a.zip", "size":...} -->|
   |<-- 2. JSON: {"type":"accept-file"} ------------------------------|
   |--- 3. Binary Chunk #1 (64 KB) ---------------------------------->|
   |--- 4. Binary Chunk #2 (64 KB) ---------------------------------->|
   |    ... (ກວດສອບ bufferedAmount < 1MB ຕະຫຼອດເວລາ) ...               |
   |--- 5. JSON: {"type":"eof", "sha256":"e3b0c442..."} ------------->|
   |<-- 6. JSON: {"type":"transfer-complete", "verified":true} -------|
```

---

## 5. ການ Deploy ຂຶ້ນ Coolify ດ້ວຍ `Dockerfile`

ໄຟລ໌ `Dockerfile` ນີ້ໃຊ້ເທັກນິກ **Multi-Stage Build** ເຊິ່ງເຮັດໃຫ້ທ່ານບໍ່ຕ້ອງ Build ໄຟລ໌ເອງໃນເຄື່ອງ ພຽງແຕ່ Push ໂຄ້ດຂຶ້ນ GitHub/GitLab ແລ້ວໃຫ້ **Coolify** ດຶງໄປ Build ອັດຕະໂນມັດ.

### 5.1 `.dockerignore` (ວາງໄວ້ທີ່ Root)
```text
node_modules
**/node_modules
**/dist
**/build
**/.dart_tool
.git
.env
```

### 5.2 `Dockerfile` (ວາງໄວ້ທີ່ Root)
```dockerfile
# =========================================================================
# STAGE 1: Build Flutter Web Client (PWA + WebAssembly/Skwasm)
# =========================================================================
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /workspace/apps/web_client

# ກ໊ອບປີ້ pubspec ກ່ອນເພື່ອໃຊ້ Docker Cache ຕອນດຶງແພັກເກັດ
COPY apps/web_client/pubspec.* ./
RUN flutter pub get

# ກ໊ອບປີ້ໂຄ້ດ Flutter ທັງໝົດ ແລ້ວສັ່ງ Build Web Release
COPY apps/web_client/ ./
RUN flutter build web --release --wasm

# =========================================================================
# STAGE 2: Build Node.js Signaling Server (TypeScript -> JS)
# =========================================================================
FROM node:20-alpine AS node-builder

RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /workspace

COPY package.json pnpm-workspace.yaml pnpm-lock.yaml* ./
COPY apps/server/package.json ./apps/server/

RUN pnpm install --frozen-lockfile=false

COPY apps/server/ ./apps/server/
RUN pnpm --filter @yonfile/server build

# =========================================================================
# STAGE 3: Production Image (ບາງ, ປອດໄພ ແລະ ໃຊ້ RAM ໜ້ອຍ)
# =========================================================================
FROM node:20-alpine AS production

RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# ຕິດຕັ້ງສະເພາະ Production Dependencies
COPY package.json pnpm-workspace.yaml ./
COPY apps/server/package.json ./apps/server/
RUN pnpm install --prod --frozen-lockfile=false

# ດຶງໄຟລ໌ Server ຈາກ Stage 2
COPY --from=node-builder /workspace/apps/server/dist ./apps/server/dist

# ດຶງໄຟລ໌ Flutter Web ຈາກ Stage 1
COPY --from=flutter-builder /workspace/apps/web_client/build/web ./apps/web_client/build/web

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["node", "apps/server/dist/index.js"]
```

---

## 6. ຄູ່ມືການຕັ້ງຄ່າໃນ Coolify & TURN Server

### 6.1 ຂັ້ນຕອນການຕັ້ງຄ່າ Application ໃນ Coolify
1. ເຂົ້າໜ້າ Dashboard ຂອງ **Coolify** ➔ ກົດ **+ Add Resource** ➔ ເລືອກ **Public / Private Repository**.
2. ເລືອກ Repository `yonfile-monorepo` ຂອງທ່ານ.
3. ໃນສ່ວນ **Build Pack** ໃຫ້ເລືອກເປັນ **`Dockerfile`** ແລະ ຕັ້ງຄ່າ:
   * **Base Directory:** `/`
   * **Dockerfile Location:** `/Dockerfile`
   * **Ports Exposes:** `3000`
4. ໃນສ່ວນ **Domains:** ໃສ່ໂດເມນຂອງທ່ານ ເຊັ່ນ `https://yonfile.la` ຫຼື `https://yonfile.com`.
   * *ໝາຍເຫດສຳຄັນ:* WebRTC ບັງຄັບໃຫ້ເວັບໄຊຕ້ອງແລ່ນເທິງ **HTTPS** ເທົ່ານັ້ນ (Coolify ຈະສ້າງ Let's Encrypt SSL ໃຫ້ອັດຕະໂນມັດ).
5. ກົດ **Deploy**!

### 6.2 ການຕັ້ງຄ່າ STUN / TURN Server (ສຳລັບການໂຍນຂ້າມ 4G/5G)
* **ຄ່າເລີ່ມຕົ້ນ (ຟຣີ):** ໃຊ້ Google Public STUN Server (`stun:stun.l.google.com:19302`) ເຊິ່ງຮອງຮັບການໂຍນໃນວົງ LAN 100% ແລະ ຂ້າມເນັດທົ່ວໄປໄດ້ປະມານ 80%.
* **ສຳລັບ Production 100% (ทะລຸ Symmetric NAT ຂອງ 4G/5G ທຸກຄ້າຍ):**
  * ທ່ານສາມາດເປີດ Service **Coturn** ໃນ Coolify (ຜ່ານ Docker Image `coturn/coturn`) ຫຼື ໃຊ້ **Cloudflare Calls TURN Service** ແລ້ວນຳເອົາຄ່າ `TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL` ໄປໃສ່ໃນ `webrtc_service.dart`.

---

## 7. ແຜນການພັດທະນາຕໍ່ຍອດ (Project Roadmap)

- [ ] **Milestone 1 (Core Setup):** ຕັ້ງຄ່າ `pnpm` Monorepo, ຂຽນ Node.js Signaling Server ແລະ ທົດສອບການຈັບຄູ່ອຸປະກອນໃນວົງ LAN ດຽວກັນ.
- [ ] **Milestone 2 (Flutter UI & Radar):** ສ້າງໜ້າຈໍ Adaptive Layout ໂທນສີສົ້ມ (`#FF6B00`), ວົງເຣດາ Animation, ແລະ ກ່ອງໃສ່ລະຫັດ PIN 6 ຕົວເລກ.
- [ ] **Milestone 3 (WebRTC File Chunking):** ເຊື່ອມຕໍ່ `flutter_webrtc`, ຂຽນລະບົບຕັດໄຟລ໌ 64KB ພ້ອມ Progress Bar ສະແດງຄວາມໄວ MB/s ແລະ ກວດສອບ SHA-256.
- [ ] **Milestone 4 (PWA & Coolify Deployment):** ເປີດໃຊ້ PWA ໃຫ້ຕິດຕັ້ງລົງໜ້າຈໍມືຖືໄດ້ ແລະ Deploy ຂຶ້ນ Coolify ດ້ວຍ Multi-stage Dockerfile.
- [ ] **Milestone 5 (Native Builds):** Compile ໂຄ້ດ Flutter ຊຸດດຽວກັນອອກເປັນແອັບ `.apk` (Android), `.ipa` (iOS), ແລະ `.exe / .dmg` (Desktop) ເພື່ອຮອງຮັບ Share Menu ໂດຍກົງຈາກລະບົບປະຕິບັດການ.
