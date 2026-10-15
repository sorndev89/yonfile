import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

import '../models/peer_device.dart';
import 'lan_discovery_stub.dart' show LanPeerFound, LanPeerLost;

/// Publishes an ephemeral YonFile presence record and discovers nearby apps.
/// This is a discovery hint only; file transfer still uses the signaling and
/// WebRTC session configured by the app.
class LanDiscoveryService {
  static const _serviceType = '_yonfile._tcp';

  LanPeerFound? _onPeerFound;
  LanPeerLost? _onPeerLost;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  BonsoirBroadcast? _broadcast;
  ServerSocket? _presenceSocket;
  String? _ownPeerId;
  int? _presencePort;

  Future<void> start({
    required LanPeerFound onPeerFound,
    required LanPeerLost onPeerLost,
  }) async {
    _onPeerFound = onPeerFound;
    _onPeerLost = onPeerLost;
    if (_discovery != null) return;
    try {
      _presenceSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _presencePort = _presenceSocket!.port;
      _presenceSocket!.listen((socket) => socket.destroy());

      final discovery = BonsoirDiscovery(type: _serviceType);
      _discovery = discovery;
      await discovery.ready;
      final events = discovery.eventStream;
      if (events == null) return;
      _subscription = events.listen(_handleEvent);
      await discovery.start();
    } catch (error) {
      // Discovery is optional. Keep the app usable if local-network access is
      // denied or the platform does not support mDNS.
      _discovery = null;
      await _presenceSocket?.close();
      _presenceSocket = null;
      _presencePort = null;
      // The UI keeps signaling-based discovery available as a fallback.
      // ignore: avoid_print
      print('YonFile local discovery unavailable: $error');
    }
  }

  Future<void> publish({
    required String peerId,
    required String name,
    required PeerDeviceType deviceType,
    required PeerOperatingSystem operatingSystem,
  }) async {
    _ownPeerId = peerId;
    final port = _presencePort;
    if (port == null) return;
    try {
      await _broadcast?.stop();
      final safeName = name.trim().isEmpty
          ? 'YonFile'
          : name.trim().substring(0, name.trim().length.clamp(0, 60).toInt());
      final service = BonsoirService(
        name:
            'YonFile-${peerId.substring(0, peerId.length.clamp(0, 8).toInt())}',
        type: _serviceType,
        port: port,
        attributes: {
          'id': peerId,
          'name': safeName,
          'kind': deviceType.name,
          'os': operatingSystem.name,
        },
      );
      final broadcast = BonsoirBroadcast(service: service);
      _broadcast = broadcast;
      await broadcast.ready;
      await broadcast.start();
    } catch (error) {
      // A failed announcement should not disrupt signaling or transfers.
      // ignore: avoid_print
      print('YonFile local presence announcement failed: $error');
    }
  }

  void _handleEvent(BonsoirDiscoveryEvent event) {
    final service = event.service;
    if (service == null || service.type != _serviceType) return;

    if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
      unawaited(service.resolve(_discovery!.serviceResolver));
      return;
    }
    final id = service.attributes['id'];
    if (id == null || id.isEmpty || id == _ownPeerId) return;
    if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
      _onPeerLost?.call(id);
      return;
    }
    if (event.type != BonsoirDiscoveryEventType.discoveryServiceResolved) {
      return;
    }

    final attributes = service.attributes;
    final deviceType = PeerDeviceType.values.firstWhere(
      (value) => value.name == attributes['kind'],
      orElse: () => PeerDeviceType.desktop,
    );
    final operatingSystem = PeerOperatingSystem.values.firstWhere(
      (value) => value.name == attributes['os'],
      orElse: () => PeerOperatingSystem.unknown,
    );
    _onPeerFound?.call(
      PeerDevice(
        id: id,
        name: attributes['name']?.trim().isNotEmpty == true
            ? attributes['name']!.trim()
            : service.name,
        deviceType: deviceType,
        operatingSystem: operatingSystem,
        scope: PeerScope.local,
      ),
    );
  }

  Future<void> unpublish() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    try {
      await _broadcast?.stop();
      await _discovery?.stop();
    } catch (_) {}
    await _presenceSocket?.close();
    _broadcast = null;
    _discovery = null;
    _presenceSocket = null;
  }
}
