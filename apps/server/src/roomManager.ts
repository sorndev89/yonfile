import crypto from 'crypto';
import { WebSocket } from 'ws';
import type {
  DeviceType,
  Peer,
  PeerScope,
  SerializedPeer,
} from './types';

/**
 * RoomManager — ຈັດການກຸ່ມ LAN IP ດຽວກັນ ແລະ ຫ້ອງ PIN 6 ຕົວເລກ.
 * Zero-storage: ບໍ່ເກັບໄຟລ໌/ຂໍ້ຄວາມ ພຽງແຕ່ routing signaling.
 */
export class RoomManager {
  private readonly peers = new Map<string, Peer>();

  get size(): number {
    return this.peers.size;
  }

  get(id: string): Peer | undefined {
    return this.peers.get(id);
  }

  register(
    ws: WebSocket,
    ip: string,
    name?: string,
    deviceType?: DeviceType,
  ): Peer {
    const existing = [...this.peers.values()].find((peer) => peer.ws === ws);
    if (existing) {
      existing.name = name?.trim().slice(0, 60) || existing.name;
      if (deviceType) existing.deviceType = deviceType;
      return existing;
    }
    const id = crypto.randomUUID();
    const peer: Peer = {
      id,
      name: name?.trim().slice(0, 60) || 'ອຸປະກອນ YonFile',
      deviceType: deviceType ?? 'desktop',
      ip,
      pinRoom: null,
      ws,
    };
    this.peers.set(id, peer);
    return peer;
  }

  remove(id: string): Peer | undefined {
    const peer = this.peers.get(id);
    if (peer) this.peers.delete(id);
    return peer;
  }

  updateName(id: string, name: string): Peer | undefined {
    const peer = this.peers.get(id);
    if (!peer || !name) return undefined;
    peer.name = name.trim().slice(0, 60);
    return peer;
  }

  /** ເຂົ້າຮ່ວມຫ້ອງ PIN, ສົ່ງຄືນທັງ peer ແລະ pin ເກົ່າ (ເພື່ອແຈ້ງ group ເກົ່າ) */
  joinPin(
    id: string,
    pin: string,
  ): { peer: Peer; oldPin: string | null } | undefined {
    const peer = this.peers.get(id);
    if (!peer || !/^\d{6}$/.test(String(pin).trim())) return undefined;
    const oldPin = peer.pinRoom;
    peer.pinRoom = String(pin).trim();
    return { peer, oldPin };
  }

  leavePin(id: string): { peer: Peer; oldPin: string | null } | undefined {
    const peer = this.peers.get(id);
    if (!peer) return undefined;
    const oldPin = peer.pinRoom;
    peer.pinRoom = null;
    return { peer, oldPin };
  }

  groupByLan(ip: string): Peer[] {
    return [...this.peers.values()].filter((p) => p.ip === ip);
  }

  groupByPin(pin: string): Peer[] {
    return [...this.peers.values()].filter((p) => p.pinRoom === pin);
  }

  private static serialize(group: Peer[], scope: PeerScope): SerializedPeer[] {
    return group.map(({ id, name, deviceType }) => ({
      id,
      name,
      deviceType,
      scope,
    }));
  }

  /** ແຈ້ງລາຍຊື່ອຸປະກອນ LAN ດຽວກັນໃຫ້ເຫັນກັນ */
  broadcastLan(ip: string): void {
    const group = this.groupByLan(ip);
    const peers = RoomManager.serialize(group, 'lan');
    RoomManager.sendAll(group, { type: 'peers-updated', scope: 'lan', peers });
  }

  /** ແຈ້ງລາຍຊື່ອຸປະກອນໃນຫ້ອງ PIN ດຽວກັນ */
  broadcastPin(pin: string): void {
    const group = this.groupByPin(pin);
    const peers = RoomManager.serialize(group, 'pin');
    RoomManager.sendAll(group, {
      type: 'peers-updated',
      scope: 'pin',
      pin,
      peers,
    });
  }

  private static sendAll(group: Peer[], message: unknown): void {
    const data = JSON.stringify(message);
    for (const member of group) {
      if (member.ws.readyState === WebSocket.OPEN) {
        member.ws.send(data);
      }
    }
  }
}
