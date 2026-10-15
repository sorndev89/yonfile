# 🚀 ຄູ່ມື Deploy ໂຍນໄຟລ໌ (YonFile) ຂຶ້ນ Coolify

ຄູ່ມືນີ້ອະທິບາຍການ Deploy **Signaling Server + Flutter Web (PWA) + TURN Server**
ຂຶ້ນ [Coolify](https://coolify.io) ດ້ວຍ `Dockerfile` ແລະ `docker-compose.yml` ທີ່ມີຢູ່ໃນໂປຣເຈັກ.

> **ຫຼັກການ:** ແອັບ YonFile (Web + APK + Desktop) **ຕ້ອງເຊື່ອມກັບ Signaling Server ສະເໝີ**
> ເພື່ອຈັບຄູ່. ຫຼັງຈັບຄູ່ແລ້ວ ໄຟລ໌/ຂໍ້ຄວາມແລ່ນ P2P (server ບໍ່ເກັບຂໍ້ມູນ).
> WebRTC ຕ້ອງການ **HTTPS** ສະເພາະ web client — ສະນັ້ນ Coolify ຕ້ອງອອກ SSL.

---

## 1. ສິ່ງທີ່ຕ້ອງກຽມ

- Coolify ຕິດຕັ້ງແລ້ວ (self-host) ແລະ ເຂົ້າໄດ້ Dashboard.
- VPS / Server ທີ່ມີ **Docker** (Coolify ຈັດການໃຫ້).
- Git Repository ຂອງໂປຣເຈັກ (GitHub / GitLab / Gitea) ທີ່ Coolify ເຂົ້າໄດ້.
- **`pnpm-lock.yaml`** ຕ້ອງ commit ເຂົ້າ repo (Dockerfile ໃຊ້ `pnpm install --frozen-lockfile`).
- **ໂດເມນ** ຊີ້ A-record ມາຫາ IP ຂອງ Server (ເຊັ່ນ `yonfile.example.com`).
- (ຖ້າໃຊ້ TURN ຂອງຕົນເອງ) IP ສາທາລະນະ ແລະ ເປີດ Firewall ports ຕາມຂໍ້ 8.

> **ໝາຍເຫດຊັບພະຍາກອນ:** Docker build ຈະ build Flutter Web ໃນ Stage 1
> (ໃຊ້ RAM ~4–6 GB ແລະ ເວລາ 5–15 ນາທີ). ໃຫ້ແນ່ໃຈວ່າ Server ມີ RAM ພຽງພໍ
> ຫຼື ປັບ Build Timeout ໃນ Coolify ໃຫ້ສູງຂຶ້ນ.

---

## 2. ກວດສອບໄຟລ໌ Deploy ໃນ Repo

ໃຫ້ແນ່ໃຈວ່າໄຟລ໌ເຫຼົ່ານີ້ຢູ່ root:

```text
yonfile/
├── Dockerfile            # Multi-stage: Flutter → Node → Production
├── docker-compose.yml    # yonfile + coturn (profile: turn)
├── .dockerignore
├── pnpm-workspace.yaml
├── package.json
└── apps/
    ├── server/           # Signaling + static host
    └── web_client/       # Flutter web (build ໃນ Docker)
```

Server ຕິດຕັ້ງຢູ່ Port **3000** ແລະມີ endpoint:
- `GET /health` — healthcheck
- `GET /api/ice-servers` — ຈ່າຍ STUN/TURN credentials
- `WS /ws` — signaling

---

## 3. ສ້າງ Resource ໃນ Coolify

1. ເຂົ້າ Dashboard → ເລືອກ **Project** (ຫຼືສ້າງໃໝ່) → ກົດ **+ New Resource**.
2. ເລືອກ **Public Repository** ຫຼື **Private Repository (GitHub App)**.
3. ເລືອກ Repository ຂອງ `yonfile` ແລະ **Branch** ທີ່ຈະ deploy (`main` / `master`).

---

## 4. ຕັ້ງຄ່າ Build (Build Pack = Dockerfile)

ໃນໜ້າ **Configuration → General**:

| ຫົວຂໍ້ | ຄ່າ |
| :-- | :-- |
| **Build Pack** | `Dockerfile` |
| **Base Directory** | `/` |
| **Dockerfile Location** | `/Dockerfile` |
| **Ports Exposes** | `3000` |
| **Direction** | ປ່ອຍຕາມຄ່າເລີ່ມຕົ້ນ |

> ບໍ່ຕ້ອງຕັ້ງ Start Command — `Dockerfile` ມີ `CMD ["node","apps/server/dist/index.js"]` ແລ້ວ.

---

## 5. ຕັ້ງຄ່າ Domain + HTTPS

ໃນ **Configuration → General → Domains**:

```text
https://yonfile.example.com
```

- Coolify ຈະຂໍ **Let's Encrypt SSL** ໃຫ້ອັດຕະໂນມັດ (ຕ້ອງໃຫ້ DNS ຊີ້ມາກ່ອນ).
- ຢ່າລືມເປີດ **HTTPS Redirect** — ຈຳເປັນສຳລັບ WebRTC ໃນ browser.
- Web client ຈະຮູ້ Signaling URL ອັດຕະໂນມັດຈາກ origin ດຽວກັນ (`wss://yonfile.example.com/ws`) — ບໍ່ຕ້ອງຕັ້ງຫຍັງເພີ່ມ.

---

## 6. ຕັ້ງຄ່າ Environment Variables

ໃນ **Configuration → Environment Variables** ໃສ່ຄ່າຕໍ່ໄປນີ້ (ເບິ່ງ [.env.example](.env.example)):

| ຊື່ | ຕົວຢ່າງ | ຄຳອະທິບາຍ |
| :-- | :-- | :-- |
| `PORT` | `3000` | Port ຂອງ server (ຕ້ອງກົງກັບ Ports Exposes) |
| `STUN_URL` | `stun:stun.l.google.com:19302` | STUN server (ຟຣີ) |
| `TURN_URL` | `turn:turn.yonfile.example.com:3478` | TURN server (ຖ້າມີ) |
| `TURN_SHARED_SECRET` | `<random-long-secret>` | Secret ສຳລັບອອກ credentials (HMAC) — ຕ້ອງຕົງກັບ Coturn |
| `TURN_REALM` | `turn.yonfile.example.com` | Realm ຂອງ Coturn |

> - ຖ້າ**ຍັງບໍ່ມີ TURN**, ປ່ອຍ `TURN_URL` / `TURN_SHARED_SECRET` ຫວ່າງໄດ້.
>   ລະບົບຈະໃຊ້ STUN ເທົ່ານັ້ນ (ພຽງພໍ LAN 100% ແລະ ຂ້າມເນັດທົ່ວໄປ ~80%).
> - ສ້າງ secret ທີ່ແຂງແຮງ: `openssl rand -hex 32`.
> - **ຢ່າ** ໃສ່ `TURN_SHARED_SECRET` ລົງໃນ browser build — server ຈະອອກ
>   credentials ຊົ່ວຄາວ (10 ນາທີ) ຜ່ານ `/api/ice-servers` ໃຫ້ເອງ.

---

## 7. Deploy

1. ກົດ **Deploy**.
2. ເບິ່ງ Build Logs ຈົນສຳເລັດ (Stage 1: Flutter build, Stage 2: TypeScript, Stage 3: Runtime).
3. ກວດສຸຂະພາບ:
   ```bash
   curl -s https://yonfile.example.com/health
   # {"status":"ok","activePeers":0}
   curl -s https://yonfile.example.com/api/ice-servers
   # {"iceServers":[{"urls":"stun:stun.l.google.com:19302"}]}
   ```
4. ເປີດເວັບ `https://yonfile.example.com` ດ້ວຍ 2 ອຸປະກອນ ໃນເຄືອຂ່າຍດຽວກັນ ເພື່ອທົດສອບການເຫັນກັນ.

---

## 8. (ທາງເລືອກ) TURN Server ສຳລັບຂ້າມ 4G/5G

ໃຊ້ສຳລັບກໍລະນີ NAT ແບບ Symmetric (ມືຖື 4G/5G ບາງຄ້າຍ) ທີ່ P2P ຊື່ອະທະຍະ.

### ທາງ A — Self-host Coturn ດ້ວຍ docker-compose

1. ໃນ Coolify ສ້າງ Resource ປະເພດ **Docker Compose** ຈາກ Repo ດຽວກັນ
   (ຫຼື ຕັ້ງ `docker-compose.yml` ນີ້ເປັນ compose build pack).
2. ຕັ້ງ env `TURN_SHARED_SECRET` ແລະ `TURN_REALM` ໃຫ້ຄືກັບບໍລິການ `yonfile`.
3. ເປີດ Service ດ້ວຍ profile `turn`:
   ```bash
   docker compose --profile turn up -d
   ```
4. ເປີດ **Firewall** ທີ່ Server:
   | Port | Protocol | ໃຊ້ສຳລັບ |
   | :-- | :-- | :-- |
   | `3478` | TCP + UDP | TURN listening |
   | `49152-65535` | UDP | Relay range |
5. ຕັ້ງ DNS `turn.yonfile.example.com` → IP Server ແລະ `TURN_URL=turn:turn.yonfile.example.com:3478`.

### ທາງ B — ໃຊ້ TURN ພາຍນອກ (Cloudflare Calls / Twilio / Metered)
- ສ້າງ TURN credentials ຈາກ Provider.
- ຕັ້ງ `TURN_URL`, `TURN_SHARED_SECRET`, `TURN_REALM` ຕາມ Provider ແນະນຳ.
- Server ຈະອອກ credentials ຊົ່ວຄາວໃຫ້ client ຜ່ານ `/api/ice-servers`.

---

## 9. Firewall / Ports ທີ່ຕ້ອງເປີດ

| Port | Protocol | ຈຸດປະສົງ |
| :-- | :-- | :-- |
| `80` | TCP | HTTP (redirect ໄປ HTTPS) |
| `443` | TCP | HTTPS + WSS (signaling) |
| `3478` | TCP + UDP | TURN (ຖ້າໃຊ້) |
| `49152-65535` | UDP | TURN relay (ຖ້າໃຊ້) |

---

## 10. ການອັບເດດ (Redeploy)

- **Auto-deploy:** ເປີດ Webhook ໃນ Coolify → push ໄປ branch ຈະ deploy ອັດຕະໂນມັດ.
- **Manual:** ກົດ **Redeploy** ໃນ Resource.
- ຖ້າແກ້ `.env` → ກົດ **Restart** ຫຼື **Redeploy**.

---

## 11. Troubleshooting

| ອາການ | ສາເຫດ/ວິທີແກ້ |
| :-- | :-- |
| ເວັບເປີດບໍ່ໄດ້ / SSL error | DNS ຍັງບໍ່ຊີ້ມາ ຫຼື Let's Encrypt ຍັງບໍ່ອອກ — ກວດ DNS + ກົດ Redeploy |
| `/health` ບໍ່ຕອບ | Port ບໍ່ກົງ — ກວດ `PORT=3000` ແລະ Ports Exposes `3000` |
| ເວັບເປີດໄດ້ ແຕ່ບໍ່ເຫັນອຸປະກອນ | ທັງສອງຢູ່ຄົນລະເຄືອຂ່າຍ → ໃຊ້ PIN; ຫຼື WebSocket `wss://` ຖືກ proxy ບລັອກ |
| ຂ້າມ 4G/5G ບໍ່ໄດ້ | ຍັງບໍ່ມີ TURN ຫຼື secret ບໍ່ຕົງກັນ — ກວດ `TURN_SHARED_SECRET` + ports |
| Build ລົ້ມດ້ວຍ OOM | Server RAM ບໍ່ພໍ (Flutter build) — ເພີ່ມ RAM/swap ຫຼື Build Timeout |
| Build ລົ້ມ: `ERR_PNPM_NO_LOCKFILE` | ບໍ່ມີ `pnpm-lock.yaml` ໃນ repo — commit ໄຟລ໌ນີ້ (Dockerfile ໃຊ້ `--frozen-lockfile`) |
| APK ຕໍ່ server ບໍ່ໄດ້ | APK ຕ້ອງ build ດ້ວຍ `--dart-define=SIGNALING_URL=wss://yonfile.example.com/ws` |

---

## 12. ໝາຍເຫດສຳລັບ Native Client (APK / Desktop)

Web ຮູ້ server URL ອັດຕະໂນມັດ, ແຕ່ **native app ຕ້ອງກຳນົດຕອນ build**:

```bash
SIGNALING_URL=wss://yonfile.example.com/ws pnpm build:apk
SIGNALING_URL=wss://yonfile.example.com/ws pnpm build:macos
```

- ຄວນໃຊ້ `wss://` (TLS) ສະເໝີ ຖ້າ server ຢູ່ອິນເຕີເນັດ.
- ຖ້າ server ຢູ່ LAN ແລະໃຊ້ `ws://` — ແອັບມີ `network_security_config` ອະນຸຍາດແລ້ວ.

**macOS installer (.dmg):** ສ້າງຕົວຕິດຕັ້ງດ້ວຍ:
```bash
SIGNALING_URL=wss://yonfile.example.com/ws pnpm build:dmg
# → dist/YonFile.dmg
```
sign ad-hoc ໂດຍ default. ຖ້າແຈກຈ່າຍໃຫ້ຄົນອື່ນ ໃຫ້ຕັ້ງ `SIGN_IDENTITY` (Developer ID)
ແລ້ວ notarize ດ້ວຍ `xcrun notarytool`. ລາຍລະອຽດເບິ່ງ [scripts/build-dmg.sh](scripts/build-dmg.sh).

---

## 13. Checklist ສັ້ນໆ

- [ ] DNS ຊີ້ມາຫາ Server ແລ້ວ
- [ ] Coolify Resource ຕັ້ງ Build Pack = Dockerfile, Port 3000
- [ ] Domain + HTTPS ເປີດແລ້ວ
- [ ] ຕັ້ງ env: `STUN_URL` (ແລະ `TURN_*` ຖ້າມີ)
- [ ] Deploy ສຳເລັດ + `/health` ຕອບ OK
- [ ] ທົດສອບ 2 ອຸປະກອນ: LAN (auto) ແລະ ຂ້າມເນັດ (PIN/QR)
- [ ] (ຂ້າມເນັດ/4G) ຕິດຕັ້ງ TURN + ເປີດ firewall ports
