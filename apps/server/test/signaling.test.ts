import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { WebSocket } from 'ws';

import { startServer, type RunningServer } from '../src/index';

let server: RunningServer;
let baseUrl: string;
let previousTrustProxy: string | undefined;

function connect(clientIp?: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(baseUrl, clientIp
      ? { headers: { 'x-forwarded-for': clientIp } }
      : undefined);
    ws.once('open', () => resolve(ws));
    ws.once('error', reject);
  });
}

type Message = Record<string, any>;

/** ລໍຖ້າຂໍ້ຄວາມທີ່ກົງກັບ predicate. */
function waitFor(
  ws: WebSocket,
  predicate: (msg: Message) => boolean,
  timeoutMs = 2000,
): Promise<Message> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      ws.off('message', onMessage);
      reject(new Error('timeout waiting for message'));
    }, timeoutMs);
    function onMessage(raw: WebSocket.RawData) {
      const msg = JSON.parse(raw.toString()) as Message;
      if (predicate(msg)) {
        clearTimeout(timer);
        ws.off('message', onMessage);
        resolve(msg);
      }
    }
    ws.on('message', onMessage);
  });
}

function send(ws: WebSocket, message: Message): void {
  ws.send(JSON.stringify(message));
}

before(async () => {
  previousTrustProxy = process.env.TRUST_PROXY;
  process.env.TRUST_PROXY = 'true';
  server = await startServer(0);
  baseUrl = `ws://127.0.0.1:${server.port}/ws`;
});

after(async () => {
  await server.close();
  if (previousTrustProxy === undefined) delete process.env.TRUST_PROXY;
  else process.env.TRUST_PROXY = previousTrustProxy;
});

test('register returns a peerId', async () => {
  const ws = await connect();
  try {
    send(ws, { type: 'register', name: 'Phone', deviceType: 'mobile' });
    const registered = await waitFor(ws, (m) => m.type === 'registered');
    assert.equal(typeof registered.peerId, 'string');
    assert.ok(registered.peerId.length > 0);
  } finally {
    ws.close();
  }
});

test('registering twice on one socket keeps one stable peer', async () => {
  const ws = await connect();
  try {
    send(ws, { type: 'register', name: 'Phone', deviceType: 'mobile' });
    const first = await waitFor(ws, (m) => m.type === 'registered');
    send(ws, { type: 'register', name: 'Phone renamed', deviceType: 'tablet' });
    const second = await waitFor(ws, (m) => m.type === 'registered');
    assert.equal(second.peerId, first.peerId);
    const health = await fetch(`http://127.0.0.1:${server.port}/health`);
    assert.equal((await health.json() as any).activePeers, 1);
  } finally {
    ws.close();
  }
});

test('invalid PINs are rejected by the signaling server', async () => {
  const ws = await connect();
  try {
    send(ws, { type: 'register', name: 'Phone' });
    await waitFor(ws, (m) => m.type === 'registered');
    send(ws, { type: 'join-pin', pin: '12abc' });
    const error = await waitFor(ws, (m) => m.type === 'error');
    assert.equal(error.code, 'invalid_pin');
  } finally {
    ws.close();
  }
});

test('ICE endpoint issues short-lived credentials and rate limits repeated requests', async () => {
  const oldUrl = process.env.TURN_URL;
  const oldSecret = process.env.TURN_SHARED_SECRET;
  process.env.TURN_URL =
    'turn:turn.example.test:3478,turn:turn.example.test:3478?transport=tcp,turns:turn.example.test:5349?transport=tcp';
  process.env.TURN_SHARED_SECRET = 'test-only-shared-secret';
  try {
    for (let attempt = 0; attempt < 30; attempt++) {
      const response = await fetch(`http://127.0.0.1:${server.port}/api/ice-servers`);
      assert.equal(response.status, 200);
    }
    const limited = await fetch(`http://127.0.0.1:${server.port}/api/ice-servers`);
    assert.equal(limited.status, 429);
    const response = await fetch(`http://127.0.0.1:${server.port}/api/ice-servers`, {
      headers: { 'x-forwarded-for': '192.0.2.77' },
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const body = await response.json() as {
      iceServers: Array<Record<string, string | string[]>>;
    };
    const turn = body.iceServers[1];
    assert.deepEqual(turn.urls, [
      'turn:turn.example.test:3478',
      'turn:turn.example.test:3478?transport=tcp',
      'turns:turn.example.test:5349?transport=tcp',
    ]);
    const [expiry] = turn.username.split(':');
    assert.ok(Number(expiry) > Math.floor(Date.now() / 1000));
    const expected = await import('node:crypto').then(({ createHmac }) =>
      createHmac('sha1', 'test-only-shared-secret').update(turn.username).digest('base64'),
    );
    assert.equal(turn.credential, expected);
  } finally {
    if (oldUrl === undefined) delete process.env.TURN_URL;
    else process.env.TURN_URL = oldUrl;
    if (oldSecret === undefined) delete process.env.TURN_SHARED_SECRET;
    else process.env.TURN_SHARED_SECRET = oldSecret;
  }
});

test('two peers on same IP see each other (LAN scope)', async () => {
  const a = await connect();
  const b = await connect();
  try {
    send(a, {
      type: 'register',
      name: 'A',
      deviceType: 'mobile',
      operatingSystem: 'android',
    });
    const aId = (await waitFor(a, (m) => m.type === 'registered')).peerId;

    let bId: string | undefined;
    const updatePromise = waitFor(
      a,
      (m) => m.type === 'peers-updated',
    );
    send(b, {
      type: 'register',
      name: 'B',
      deviceType: 'desktop',
      operatingSystem: 'macos',
    });
    bId = (await waitFor(b, (m) => m.type === 'registered')).peerId;
    const update = await updatePromise;
    assert.equal(update.scope, 'lan');
    const ids = update.peers.map((p: any) => p.id);
    assert.ok(ids.includes(aId));
    assert.ok(ids.includes(bId));
    assert.equal(
      update.peers.find((peer: any) => peer.id === aId).operatingSystem,
      'android',
    );
    assert.equal(
      update.peers.find((peer: any) => peer.id === bId).operatingSystem,
      'macos',
    );
  } finally {
    a.close();
    b.close();
  }
});

test('forwarded client IP headers are ignored unless proxy trust is enabled', async () => {
  process.env.TRUST_PROXY = 'false';
  const a = await connect('198.51.100.10');
  const b = await connect('203.0.113.20');
  try {
    send(a, { type: 'register', name: 'A' });
    const aId = (await waitFor(a, (m) => m.type === 'registered')).peerId;
    const updatePromise = waitFor(
      a,
      (m) => m.type === 'peers-updated' && m.scope === 'lan',
    );
    send(b, { type: 'register', name: 'B' });
    const bId = (await waitFor(b, (m) => m.type === 'registered')).peerId;
    const update = await updatePromise;
    assert.ok(update.peers.some((peer: any) => peer.id === aId));
    assert.ok(update.peers.some((peer: any) => peer.id === bId));
  } finally {
    process.env.TRUST_PROXY = 'true';
    a.close();
    b.close();
  }
});

test('same-network peers must share a PIN before signaling is relayed', async () => {
  const a = await connect();
  const b = await connect();
  try {
    send(a, { type: 'register', name: 'Sender', deviceType: 'mobile' });
    await waitFor(a, (m) => m.type === 'registered');
    send(b, { type: 'register', name: 'Receiver', deviceType: 'desktop' });
    const bId = (await waitFor(b, (m) => m.type === 'registered')).peerId;

    let receivedSignal = false;
    const onMessage = (raw: WebSocket.RawData) => {
      if ((JSON.parse(raw.toString()) as Message).type === 'signal') {
        receivedSignal = true;
      }
    };
    b.on('message', onMessage);
    send(a, {
      type: 'signal',
      targetId: bId,
      payload: { type: 'offer-file', name: 'a.zip', size: 10 },
    });
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(receivedSignal, false);

    const joinedPromise = waitFor(
      a,
      (m) =>
        m.type === 'peers-updated' &&
        m.scope === 'pin' &&
        m.peers.some((peer: any) => peer.id === bId),
    );
    send(a, { type: 'join-pin', pin: '123456' });
    send(b, { type: 'join-pin', pin: '123456' });
    await joinedPromise;
    send(a, {
      type: 'signal',
      targetId: bId,
      payload: { type: 'offer-file', name: 'a.zip', size: 10 },
    });

    const relayed = await waitFor(b, (m) => m.type === 'signal');
    assert.equal(relayed.senderName, 'Sender');
    assert.deepEqual(relayed.payload, {
      type: 'offer-file',
      name: 'a.zip',
      size: 10,
    });
    b.off('message', onMessage);
  } finally {
    a.close();
    b.close();
  }
});

test('signal is blocked between different networks until peers share a PIN', async () => {
  const a = await connect('198.51.100.10');
  const b = await connect('203.0.113.20');
  try {
    send(a, { type: 'register', name: 'A' });
    await waitFor(a, (m) => m.type === 'registered');
    send(b, { type: 'register', name: 'B' });
    const bId = (await waitFor(b, (m) => m.type === 'registered')).peerId;

    let receivedSignal = false;
    const onMessage = (raw: WebSocket.RawData) => {
      if ((JSON.parse(raw.toString()) as Message).type === 'signal') {
        receivedSignal = true;
      }
    };
    b.on('message', onMessage);
    send(a, { type: 'signal', targetId: bId, payload: { type: 'test' } });
    await new Promise((resolve) => setTimeout(resolve, 50));
    assert.equal(receivedSignal, false);

    const joinedPromise = waitFor(
      a,
      (m) =>
        m.type === 'peers-updated' &&
        m.scope === 'pin' &&
        m.peers.some((peer: any) => peer.id === bId),
    );
    send(a, { type: 'join-pin', pin: '234567' });
    send(b, { type: 'join-pin', pin: '234567' });
    await joinedPromise;
    send(a, { type: 'signal', targetId: bId, payload: { type: 'test' } });
    await waitFor(b, (m) => m.type === 'signal' && m.senderName === 'A');
    b.off('message', onMessage);
  } finally {
    a.close();
    b.close();
  }
});

test('join-pin groups peers and leaving removes them', async () => {
  const a = await connect();
  const b = await connect();
  try {
    send(a, { type: 'register', name: 'A', deviceType: 'mobile' });
    const aId = (await waitFor(a, (m) => m.type === 'registered')).peerId;

    send(b, { type: 'register', name: 'B', deviceType: 'desktop' });
    const bId = (await waitFor(b, (m) => m.type === 'registered')).peerId;

    send(a, { type: 'join-pin', pin: '849201' });
    send(b, { type: 'join-pin', pin: '849201' });

    const pinUpdate = await waitFor(
      a,
      (m) =>
        m.type === 'peers-updated' &&
        m.scope === 'pin' &&
        m.pin === '849201' &&
        m.peers.some((p: any) => p.id === bId),
    );
    assert.equal(pinUpdate.peers.length, 2);
    assert.ok(pinUpdate.peers.some((p: any) => p.id === aId));

    send(b, { type: 'leave-pin' });
    const afterLeave = await waitFor(
      a,
      (m) =>
        m.type === 'peers-updated' &&
        m.scope === 'pin' &&
        m.peers.every((p: any) => p.id !== bId),
    );
    assert.equal(afterLeave.peers.length, 1);
  } finally {
    a.close();
    b.close();
  }
});

test('peer list updates when a peer disconnects', async () => {
  const a = await connect();
  const b = await connect();
  try {
    send(a, { type: 'register', name: 'A', deviceType: 'mobile' });
    await waitFor(a, (m) => m.type === 'registered');
    send(b, { type: 'register', name: 'B', deviceType: 'desktop' });
    const bId = (await waitFor(b, (m) => m.type === 'registered')).peerId;

    await waitFor(
      a,
      (m) => m.type === 'peers-updated' && m.peers.some((p: any) => p.id === bId),
    );

    b.close();
    const afterClose = await waitFor(
      a,
      (m) =>
        m.type === 'peers-updated' && m.peers.every((p: any) => p.id !== bId),
    );
    assert.ok(afterClose.peers.every((p: any) => p.id !== bId));
  } finally {
    a.close();
  }
});
