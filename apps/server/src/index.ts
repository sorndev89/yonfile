import express from 'express';
import http from 'http';
import path from 'path';
import crypto from 'crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { RoomManager } from './roomManager';
import type { InboundMessage, SignalMessage } from './types';

const app = express();
const server = http.createServer(app);
const allowedOrigins = new Set(
  (process.env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
);
const wss = new WebSocketServer({
  server,
  path: '/ws',
  maxPayload: 256 * 1024,
  verifyClient: ({ origin, req }, done) => {
    // Native apps omit Origin. Browsers must use the same host or an explicit allowlist.
    if (!origin) return done(true);
    try {
      const parsed = new URL(origin);
      const sameHost = parsed.host === req.headers.host;
      done(sameHost || allowedOrigins.has(parsed.origin), 403, 'Origin not allowed');
    } catch {
      done(false, 403, 'Invalid Origin');
    }
  },
});
const rooms = new RoomManager();
const pinAttempts = new Map<string, number[]>();
const MAX_SIGNAL_BYTES = 256 * 1024;
const PIN_ATTEMPT_WINDOW_MS = 60_000;
const MAX_PIN_ATTEMPTS_PER_WINDOW = 20;
const iceAttempts = new Map<string, number[]>();
const MAX_ICE_REQUESTS_PER_WINDOW = 30;

/**
 * ດຶງ Public IP ແທ້ຈາກ Reverse Proxy (Coolify / Traefik / Cloudflare / Nginx).
 * ໃຊ້ສຳລັບຈັດກຸ່ມອຸປະກອນ LAN ດຽວກັນ (Public IP ດຽວກັນ).
 */
function extractClientIp(req: http.IncomingMessage): string {
  if (process.env.TRUST_PROXY !== 'true') {
    return req.socket.remoteAddress || '127.0.0.1';
  }
  const cfIp = req.headers['cf-connecting-ip'];
  const xRealIp = req.headers['x-real-ip'];
  const xForwardedFor = req.headers['x-forwarded-for'];

  if (typeof cfIp === 'string' && cfIp.length > 0) return cfIp.trim();
  if (typeof xRealIp === 'string' && xRealIp.length > 0) return xRealIp.trim();
  if (typeof xForwardedFor === 'string' && xForwardedFor.length > 0) {
    return xForwardedFor.split(',')[0].trim();
  }
  return req.socket.remoteAddress || '127.0.0.1';
}

wss.on('connection', (ws, req) => {
  const clientIp = extractClientIp(req);
  let peerId: string | null = null;

  ws.on('message', (rawMessage) => {
    if (Buffer.byteLength(rawMessage.toString()) > MAX_SIGNAL_BYTES) {
      ws.close(1009, 'Message too large');
      return;
    }
    let decoded: unknown;
    try {
      decoded = JSON.parse(rawMessage.toString());
    } catch (err) {
      console.error('Invalid WS message:', err);
      return;
    }
    if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) return;
    const msg = decoded as InboundMessage;

    switch (msg.type) {
      // 1. ລົງທະບຽນອຸປະກອນເມື່ອເປີດເວັບ
      case 'register': {
        const deviceType =
          msg.deviceType === 'mobile' ||
          msg.deviceType === 'tablet' ||
          msg.deviceType === 'desktop'
            ? msg.deviceType
            : 'desktop';
        const operatingSystem =
          msg.operatingSystem === 'android' ||
          msg.operatingSystem === 'ios' ||
          msg.operatingSystem === 'macos' ||
          msg.operatingSystem === 'windows' ||
          msg.operatingSystem === 'linux' ||
          msg.operatingSystem === 'web' ||
          msg.operatingSystem === 'unknown'
            ? msg.operatingSystem
            : 'unknown';
        const name = typeof msg.name === 'string' ? msg.name : undefined;
        const peer = rooms.register(
          ws,
          clientIp,
          name,
          deviceType,
          operatingSystem,
        );
        peerId = peer.id;
        ws.send(
          JSON.stringify({ type: 'registered', peerId: peer.id, ip: clientIp }),
        );
        rooms.broadcastLan(clientIp);
        break;
      }

      // 2. ປ່ຽນຊື່ອຸປະກອນ
      case 'update-name': {
        if (!peerId || typeof msg.name !== 'string') break;
        const peer = rooms.updateName(peerId, msg.name);
        if (peer) {
          rooms.broadcastLan(peer.ip);
          if (peer.pinRoom) rooms.broadcastPin(peer.pinRoom);
        }
        break;
      }

      // 3. ເຂົ້າຮ່ວມຫ້ອງ PIN (ໂຍນຂ້າມ Network)
      case 'join-pin': {
        if (!peerId) break;
        if (typeof msg.pin !== 'string' || !/^\d{6}$/.test(msg.pin.trim())) {
          ws.send(JSON.stringify({ type: 'error', code: 'invalid_pin' }));
          break;
        }
        const attempts = (pinAttempts.get(clientIp) ?? []).filter(
          (time) => Date.now() - time < PIN_ATTEMPT_WINDOW_MS,
        );
        if (attempts.length >= MAX_PIN_ATTEMPTS_PER_WINDOW) {
          ws.send(JSON.stringify({ type: 'error', code: 'pin_rate_limited' }));
          pinAttempts.set(clientIp, attempts);
          break;
        }
        attempts.push(Date.now());
        pinAttempts.set(clientIp, attempts);
        if (pinAttempts.size > 10_000) {
          for (const [ip, times] of pinAttempts) {
            if (times.every((time) => Date.now() - time >= PIN_ATTEMPT_WINDOW_MS)) {
              pinAttempts.delete(ip);
            }
          }
        }
        const result = rooms.joinPin(peerId, msg.pin);
        if (result) {
          if (result.oldPin && result.oldPin !== result.peer.pinRoom) {
            rooms.broadcastPin(result.oldPin);
          }
          rooms.broadcastPin(result.peer.pinRoom!);
        }
        break;
      }

      // 4. ອອກຈາກຫ້ອງ PIN
      case 'leave-pin': {
        if (!peerId) break;
        const result = rooms.leavePin(peerId);
        if (result?.oldPin) rooms.broadcastPin(result.oldPin);
        break;
      }

      // 5. ສົ່ງຕໍ່ WebRTC Signaling (offer / answer / ICE / file meta)
      case 'signal': {
        if (!peerId || typeof msg.targetId !== 'string' || !msg.payload || typeof msg.payload !== 'object') break;
        relaySignal(peerId, msg);
        break;
      }
    }
  });

  ws.on('close', () => {
    if (!peerId) return;
    const peer = rooms.remove(peerId);
    if (peer) {
      rooms.broadcastLan(peer.ip);
      if (peer.pinRoom) rooms.broadcastPin(peer.pinRoom);
    }
  });

  ws.on('error', (err) => {
    console.error(`WS error (${peerId ?? 'unregistered'}):`, err.message);
  });
});

function relaySignal(senderId: string, msg: SignalMessage): void {
  const target = rooms.get(msg.targetId);
  const sender = rooms.get(senderId);
  if (!target || !sender) return;
  if (target.ws.readyState !== WebSocket.OPEN) return;
  // All signaling, including file offers and WebRTC negotiation, requires a shared PIN room.
  if (!sender.pinRoom || sender.pinRoom !== target.pinRoom) {
    return;
  }

  target.ws.send(
    JSON.stringify({
      type: 'signal',
      senderId,
      senderName: sender.name,
      payload: msg.payload,
    }),
  );
}

// Healthcheck Endpoint ສຳລັບ Coolify
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok', activePeers: rooms.size });
});

app.get('/api/ice-servers', (req, res) => {
  const ip = extractClientIp(req);
  const now = Date.now();
  const recentAttempts = (iceAttempts.get(ip) ?? []).filter(
    (time) => now - time < PIN_ATTEMPT_WINDOW_MS,
  );
  if (recentAttempts.length >= MAX_ICE_REQUESTS_PER_WINDOW) {
    res.setHeader('Retry-After', '60');
    res.status(429).json({ error: 'rate_limited' });
    return;
  }
  recentAttempts.push(now);
  iceAttempts.set(ip, recentAttempts);
  if (iceAttempts.size > 10_000) {
    for (const [key, times] of iceAttempts) {
      if (times.every((time) => now - time >= PIN_ATTEMPT_WINDOW_MS)) {
        iceAttempts.delete(key);
      }
    }
  }

  const stunUrl = process.env.STUN_URL || 'stun:stun.l.google.com:19302';
  // Comma-separated TURN URLs let deployments offer UDP, TCP, and TLS
  // transports (for example turn:host:3478,turn:host:3478?transport=tcp,
  // turns:host:5349?transport=tcp) with the same short-lived credentials.
  const turnUrls = (process.env.TURN_URL ?? '')
    .split(',')
    .map((url) => url.trim())
    .filter(Boolean);
  const sharedSecret = process.env.TURN_SHARED_SECRET;
  const iceServers: Array<Record<string, string | string[]>> = [{ urls: stunUrl }];

  if (turnUrls.length > 0 && sharedSecret && sharedSecret !== 'CHANGE_ME_TURN_SECRET') {
    const expiresAt = Math.floor(Date.now() / 1000) + 10 * 60;
    const username = `${expiresAt}:${crypto.randomUUID()}`;
    const credential = crypto
      .createHmac('sha1', sharedSecret)
      .update(username)
      .digest('base64');
    iceServers.push({ urls: turnUrls, username, credential });
  }

  res.setHeader('Cache-Control', 'no-store');
  res.json({ iceServers });
});

// ເຊີບໄຟລ໌ Flutter Web ທີ່ Build ແລ້ວ (dist/index.js -> ../../web_client/build/web)
const flutterWebDir = path.join(__dirname, '../../web_client/build/web');
app.use(express.static(flutterWebDir));
app.get('*', (_req, res) => {
  res.sendFile(path.join(flutterWebDir, 'index.html'));
});

export interface RunningServer {
  port: number;
  close: () => Promise<void>;
}

/** ເລີ່ມ server ແລະ ສົ່ງຄືນ port ຕົວຈິງ (ໃຊ້ port 0 ເພື່ອ random ໃນ test). */
export function startServer(
  port = Number(process.env.PORT) || 3000,
): Promise<RunningServer> {
  return new Promise((resolve) => {
    server.listen(port, '0.0.0.0', () => {
      const address = server.address();
      const actualPort =
        typeof address === 'object' && address ? address.port : port;
      console.log(`🟠 YonFile Server is running on http://0.0.0.0:${actualPort}`);
      resolve({
        port: actualPort,
        close: () =>
          new Promise<void>((done) => {
            wss.close();
            server.close(() => done());
          }),
      });
    });
  });
}

if (require.main === module) {
  startServer();

  // Graceful shutdown
  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.on(signal, () => {
      console.log(`\n${signal} received — shutting down...`);
      wss.close();
      server.close(() => process.exit(0));
    });
  }
}
