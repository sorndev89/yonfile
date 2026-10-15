import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import '../core/constants/app_config.dart';
import '../models/peer_device.dart';

enum SignalingStatus { disconnected, connecting, connected }

class PeersUpdatedEvent {
  final PeerScope scope;
  final String? pin;
  final List<PeerDevice> peers;
  const PeersUpdatedEvent({required this.scope, required this.peers, this.pin});
}

class SignalEvent {
  final String senderId;
  final String senderName;
  final Map<String, dynamic> payload;
  const SignalEvent({
    required this.senderId,
    required this.senderName,
    required this.payload,
  });
}

/// SignalingService — WebSocket client ລົມກັບ Node.js Signaling Server.
class SignalingService {
  SignalingService({String? url}) : _url = url ?? AppConfig.signalingUrl;

  String _url;
  String get url => _url;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _manuallyClosed = false;
  bool _connecting = false;
  int _endpointGeneration = 0;

  String? peerId;
  String? publicIp;

  String _name = 'ອຸປະກອນ YonFile';
  PeerDeviceType _deviceType = PeerDeviceType.desktop;
  String? _joinedPin;

  final _statusController = StreamController<SignalingStatus>.broadcast();
  final _registeredController = StreamController<String>.broadcast();
  final _peersController = StreamController<PeersUpdatedEvent>.broadcast();
  final _signalController = StreamController<SignalEvent>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<SignalingStatus> get statusStream => _statusController.stream;
  Stream<String> get registeredStream => _registeredController.stream;
  Stream<PeersUpdatedEvent> get peersStream => _peersController.stream;
  Stream<SignalEvent> get signalStream => _signalController.stream;
  Stream<String> get errorStream => _errorController.stream;

  bool get isConnected => _channel != null && peerId != null;
  bool get usesLocalEndpoint => Uri.tryParse(_url)?.port == 3001;

  Future<void> connect() async {
    if (_manuallyClosed || _connecting || _channel != null) return;
    _connecting = true;
    final generation = _endpointGeneration;
    _manuallyClosed = false;
    _statusController.add(SignalingStatus.connecting);

    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(_url));
      _channel = channel;
      await channel.ready;
      if (_manuallyClosed || generation != _endpointGeneration) {
        await channel.sink.close(ws_status.normalClosure);
        return;
      }

      _subscription = channel.stream.listen(
        _handleRawMessage,
        onError: (Object error) {
          debugPrint('Signaling error: $error');
          _scheduleReconnect();
        },
        onDone: () {
          _statusController.add(SignalingStatus.disconnected);
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      _statusController.add(SignalingStatus.connected);
      // ລົງທະບຽນອຸປະກອນທັນທີ
      _send({
        'type': 'register',
        'name': _name,
        'deviceType': _deviceType.name,
      });
    } catch (error) {
      debugPrint('Signaling connect failed: $error');
      if (identical(_channel, channel)) _channel = null;
      if (generation == _endpointGeneration && !_manuallyClosed) {
        _scheduleReconnect();
      }
    } finally {
      if (generation == _endpointGeneration) _connecting = false;
    }
  }

  /// Switches signaling to another endpoint, used for an offline LAN host.
  Future<void> useEndpoint(String endpoint) async {
    _endpointGeneration++;
    _reconnectTimer?.cancel();
    _manuallyClosed = true;
    final old = _channel;
    _channel = null;
    peerId = null;
    await _subscription?.cancel();
    _subscription = null;
    _connecting = false;
    try {
      await old?.sink.close(ws_status.goingAway);
    } catch (_) {}
    _url = endpoint;
    _manuallyClosed = false;
    await connect();
  }

  void _handleDisconnect() {
    peerId = null;
    _channel = null;
    if (!_manuallyClosed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _statusController.add(SignalingStatus.disconnected);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!_manuallyClosed && _channel == null) connect();
    });
  }

  void _handleRawMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('Invalid signaling message: $error');
      return;
    }

    switch (msg['type']) {
      case 'registered':
        peerId = msg['peerId'] as String?;
        publicIp = msg['ip'] as String?;
        if (peerId != null) _registeredController.add(peerId!);
        if (_joinedPin != null) {
          _send({'type': 'join-pin', 'pin': _joinedPin});
        }
        break;
      case 'peers-updated':
        final list = (msg['peers'] as List<dynamic>? ?? [])
            .map((e) => PeerDevice.fromJson(e as Map<String, dynamic>))
            .toList();
        _peersController.add(
          PeersUpdatedEvent(
            scope: (msg['scope'] as String?) == 'pin'
                ? PeerScope.pin
                : PeerScope.lan,
            pin: msg['pin'] as String?,
            peers: list,
          ),
        );
        break;
      case 'signal':
        _signalController.add(
          SignalEvent(
            senderId: msg['senderId'] as String,
            senderName: (msg['senderName'] as String?) ?? 'YonFile',
            payload: (msg['payload'] as Map?)?.cast<String, dynamic>() ?? {},
          ),
        );
        break;
      case 'error':
        final code = msg['code'];
        if (code is String && !_errorController.isClosed) {
          _errorController.add(code);
        }
        break;
    }
  }

  void register(String name, PeerDeviceType deviceType) {
    _name = name.trim().isEmpty ? 'ອຸປະກອນ YonFile' : name.trim();
    _deviceType = deviceType;
    if (isConnected) {
      _send({
        'type': 'register',
        'name': _name,
        'deviceType': _deviceType.name,
      });
    }
  }

  void updateName(String name) {
    _name = name.trim().isEmpty ? _name : name.trim();
    _send({'type': 'update-name', 'name': _name});
  }

  void joinPin(String pin) {
    _joinedPin = pin.trim();
    _send({'type': 'join-pin', 'pin': _joinedPin});
  }

  void leavePin() {
    _joinedPin = null;
    _send({'type': 'leave-pin'});
  }

  void sendSignal(String targetId, Map<String, dynamic> payload) {
    _send({'type': 'signal', 'targetId': targetId, 'payload': payload});
  }

  void _send(Map<String, dynamic> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (error) {
      debugPrint('Signaling send failed: $error');
    }
  }

  void dispose() {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    try {
      _channel?.sink.close(ws_status.normalClosure);
    } catch (_) {}
    _statusController.close();
    _registeredController.close();
    _peersController.close();
    _signalController.close();
    _errorController.close();
  }
}
