import type { WebSocket } from 'ws';

export type DeviceType = 'mobile' | 'tablet' | 'desktop';

export type PeerScope = 'lan' | 'pin';

/** ອຸປະກອນທີ່ເຊື່ອມຕໍ່ກັບ Signaling Server */
export interface Peer {
  id: string;
  name: string;
  deviceType: DeviceType;
  /** Public IP ທີ່ດຶງຈາກ Reverse Proxy ໃຊ້ຈັດກຸ່ມ LAN */
  ip: string;
  /** ລະຫັດຫ້ອງ 6 ຕົວເລກ ສຳລັບໂຍນຂ້າມເຄືອຂ່າຍ */
  pinRoom: string | null;
  ws: WebSocket;
}

/** ໂຄງສ້າງອຸປະກອນທີ່ສົ່ງໄປຫາ Client (ບໍ່ມີ ws / ip ດ້ວຍເຫດຜົນຄວາມປອດໄພ) */
export interface SerializedPeer {
  id: string;
  name: string;
  deviceType: DeviceType;
  scope: PeerScope;
}

/* ----------------------------- Inbound Messages ----------------------------- */

export interface RegisterMessage {
  type: 'register';
  name?: string;
  deviceType?: DeviceType;
}

export interface UpdateNameMessage {
  type: 'update-name';
  name: string;
}

export interface JoinPinMessage {
  type: 'join-pin';
  pin: string;
}

export interface LeavePinMessage {
  type: 'leave-pin';
}

export interface SignalMessage {
  type: 'signal';
  targetId: string;
  payload: unknown;
}

export type InboundMessage =
  | RegisterMessage
  | UpdateNameMessage
  | JoinPinMessage
  | LeavePinMessage
  | SignalMessage;

/* ---------------------------- Outbound Messages ----------------------------- */

export interface RegisteredMessage {
  type: 'registered';
  peerId: string;
  ip: string;
}

export interface PeersUpdatedMessage {
  type: 'peers-updated';
  scope: PeerScope;
  pin?: string;
  peers: SerializedPeer[];
}

export interface SignalRelayMessage {
  type: 'signal';
  senderId: string;
  senderName: string;
  payload: unknown;
}

export type OutboundMessage =
  | RegisteredMessage
  | PeersUpdatedMessage
  | SignalRelayMessage;
