import '../models/peer_device.dart';

typedef LanPeerFound = void Function(PeerDevice peer);
typedef LanPeerLost = void Function(String peerId);

class LanDiscoveryService {
  Future<void> start({
    required LanPeerFound onPeerFound,
    required LanPeerLost onPeerLost,
  }) async {}

  Future<void> publish({
    required String peerId,
    required String name,
    required PeerDeviceType deviceType,
    required PeerOperatingSystem operatingSystem,
  }) async {}

  Future<void> unpublish() async {}

  Future<void> dispose() async {}
}
