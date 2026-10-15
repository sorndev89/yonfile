import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Small, in-memory signaling relay for transfers on an isolated LAN.
/// File bytes still travel directly through WebRTC between devices.
class LocalSignalingHost {
  HttpServer? _server;
  final Map<String, _LocalPeer> _peers = {};
  int _sequence = 0;
  int get port => _server?.port ?? 0;

  Future<List<String>> start({int port = 3001}) async {
    if (_server != null) return _localAddresses();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
    return _localAddresses();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/ws' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    _LocalPeer? peer;
    socket.listen(
      (dynamic raw) {
        try {
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = message['type'];
          if (type == 'register') {
            if (peer == null) {
              peer = _LocalPeer(
                id: 'lan-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
                socket: socket,
              );
              _peers[peer!.id] = peer!;
            }
            peer!
              ..name = _cleanName(message['name'] as String?)
              ..deviceType = _cleanDeviceType(message['deviceType'] as String?)
              ..operatingSystem = _cleanOperatingSystem(
                message['operatingSystem'] as String?,
              );
            _send(peer!, {
              'type': 'registered',
              'peerId': peer!.id,
              'ip': 'local',
            });
            _broadcastLan();
          } else if (peer != null) {
            _handleMessage(peer!, message);
          }
        } catch (_) {
          _sendRaw(socket, {'type': 'error', 'code': 'invalid-message'});
        }
      },
      onDone: () => _remove(peer),
      onError: (_) => _remove(peer),
      cancelOnError: true,
    );
  }

  void _handleMessage(_LocalPeer peer, Map<String, dynamic> message) {
    switch (message['type']) {
      case 'register':
      case 'update-name':
        peer.name = _cleanName(message['name'] as String?);
        if (message['deviceType'] is String) {
          peer.deviceType = _cleanDeviceType(message['deviceType'] as String?);
        }
        if (message['operatingSystem'] is String) {
          peer.operatingSystem = _cleanOperatingSystem(
            message['operatingSystem'] as String?,
          );
        }
        _broadcastLan();
        if (peer.pin != null) _broadcastPin(peer.pin!);
        break;
      case 'join-pin':
        final pin = (message['pin'] as String? ?? '').trim();
        if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
          _send(peer, {'type': 'error', 'code': 'invalid-pin'});
          return;
        }
        final oldPin = peer.pin;
        peer.pin = pin;
        _broadcastLan();
        if (oldPin != null) _broadcastPin(oldPin);
        _broadcastPin(pin);
        break;
      case 'leave-pin':
        final oldPin = peer.pin;
        peer.pin = null;
        _broadcastLan();
        if (oldPin != null) _broadcastPin(oldPin);
        break;
      case 'signal':
        final targetId = message['targetId'];
        final target = targetId is String ? _peers[targetId] : null;
        if (target == null || peer.pin == null || target.pin != peer.pin) {
          _send(peer, {'type': 'error', 'code': 'peer-not-found'});
          return;
        }
        _send(target, {
          'type': 'signal',
          'senderId': peer.id,
          'senderName': peer.name,
          'payload': message['payload'] ?? <String, dynamic>{},
        });
        break;
    }
  }

  void _remove(_LocalPeer? peer) {
    if (peer == null || _peers.remove(peer.id) == null) return;
    final pin = peer.pin;
    _broadcastLan();
    if (pin != null) _broadcastPin(pin);
  }

  void _broadcastLan() => _broadcast(_peers.values.toList(), 'lan');

  void _broadcastPin(String pin) => _broadcast(
    _peers.values.where((peer) => peer.pin == pin).toList(),
    'pin',
    pin: pin,
  );

  void _broadcast(List<_LocalPeer> peers, String scope, {String? pin}) {
    final message = {
      'type': 'peers-updated',
      'scope': scope,
      'pin': ?pin,
      'peers': peers
          .map(
            (peer) => {
              'id': peer.id,
              'name': peer.name,
              'deviceType': peer.deviceType,
              'operatingSystem': peer.operatingSystem,
              'scope': scope,
            },
          )
          .toList(),
    };
    for (final peer in peers) {
      _send(peer, message);
    }
  }

  Future<List<String>> _localAddresses() async {
    final result = <String>[];
    for (final interface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    )) {
      for (final address in interface.addresses) {
        final ip = address.address;
        if (!address.isLoopback &&
            (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip))) {
          result.add(address.address);
        }
      }
    }
    return result.toSet().toList();
  }

  String _cleanName(String? name) {
    final value = name?.trim().isNotEmpty == true
        ? name!.trim()
        : 'ອຸປະກອນ YonFile';
    return value.substring(0, value.length.clamp(0, 60).toInt());
  }

  String _cleanDeviceType(String? type) =>
      const {'mobile', 'tablet', 'desktop'}.contains(type) ? type! : 'desktop';

  String _cleanOperatingSystem(String? system) =>
      const {
        'android',
        'ios',
        'macos',
        'windows',
        'linux',
        'web',
      }.contains(system)
      ? system!
      : 'unknown';

  void _send(_LocalPeer peer, Map<String, dynamic> message) =>
      _sendRaw(peer.socket, message);

  void _sendRaw(WebSocket socket, Map<String, dynamic> message) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(message));
  }

  Future<void> stop() async {
    for (final peer in _peers.values.toList()) {
      await peer.socket.close(WebSocketStatus.goingAway);
    }
    _peers.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

class _LocalPeer {
  _LocalPeer({required this.id, required this.socket});
  final String id;
  final WebSocket socket;
  String name = 'ອຸປະກອນ YonFile';
  String deviceType = 'desktop';
  String operatingSystem = 'unknown';
  String? pin;
}
