import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../core/constants/app_config.dart';
import 'signaling_service.dart';

/// ຂໍ້ຄວາມທີ່ຮັບເຂົ້າມາຈາກ DataChannel ຂອງ peer ໃດໜຶ່ງ.
class PeerMessage {
  final String peerId;
  final RTCDataChannelMessage message;
  const PeerMessage(this.peerId, this.message);

  bool get isBinary => message.isBinary;
  String get text => message.text;
  Uint8List get binary => message.binary;
}

/// ການປ່ຽນແປງສະຖານະຂອງ DataChannel.
class PeerChannelState {
  final String peerId;
  final RTCDataChannelState state;
  const PeerChannelState(this.peerId, this.state);

  bool get isOpen => state == RTCDataChannelState.RTCDataChannelOpen;
}

class PeerRouteState {
  const PeerRouteState(this.peerId, this.route);

  final String peerId;
  /// `direct`, `relay`, or `unknown` until ICE exposes a selected pair.
  final String route;
}

class _PeerSession {
  _PeerSession({required this.peerId, required this.pc});

  final String peerId;
  final RTCPeerConnection pc;
  RTCDataChannel? channel;
  bool remoteDescriptionSet = false;
  bool makingOffer = false;
  bool ignoreOffer = false;
  bool offerStarted = false;
  final List<RTCIceCandidate> pendingCandidates = [];
  final Completer<RTCDataChannel> openCompleter = Completer<RTCDataChannel>();
  final Completer<String> failureCompleter = Completer<String>();
}

/// WebRtcService — ຈັດການ RTCPeerConnection & RTCDataChannel ຕໍ່ peer.
/// ໄຟລ໌ແລ່ນແບບ P2P ຜ່ານ DTLS ໂດຍກົງ.
class WebRtcService {
  WebRtcService(this.signaling) {
    _signalSub = signaling.signalStream.listen(_onSignal);
  }

  final SignalingService signaling;
  StreamSubscription<SignalEvent>? _signalSub;

  final Map<String, _PeerSession> _sessions = {};
  final Map<String, Future<_PeerSession>> _creatingSessions = {};

  final _messageController = StreamController<PeerMessage>.broadcast();
  final _stateController = StreamController<PeerChannelState>.broadcast();
  final _routeController = StreamController<PeerRouteState>.broadcast();
  final _disconnectController = StreamController<String>.broadcast();

  Stream<PeerMessage> get messages => _messageController.stream;
  Stream<PeerChannelState> get channelStates => _stateController.stream;
  Stream<PeerRouteState> get routeStates => _routeController.stream;
  Stream<String> get disconnects => _disconnectController.stream;

  bool isOpen(String peerId) =>
      _sessions[peerId]?.channel?.state ==
      RTCDataChannelState.RTCDataChannelOpen;

  /// ເປີດການເຊື່ອມຕໍ່ແບບ initiator (ສ້າງ offer + data channel).
  Future<RTCDataChannel> connect(String peerId) async {
    final session = await _ensureSession(peerId, initiator: true);
    return session.channel!;
  }

  /// ລໍຖ້າໃຫ້ DataChannel ພ້ອມໃຊ້ງານ.
  Future<RTCDataChannel> waitUntilOpen(
    String peerId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final session = _sessions[peerId];
    if (session == null) throw StateError('No session for $peerId');
    if (session.channel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      return session.channel!;
    }
    try {
      final result = await Future.any<Object>([
        session.openCompleter.future,
        session.failureCompleter.future,
      ]).timeout(timeout);
      if (result is String) throw StateError(result);
      return result as RTCDataChannel;
    } on TimeoutException {
      await closeSession(peerId);
      throw TimeoutException(
        'WebRTC connection timed out. Check both internet connections and '
        'confirm that the signaling server provides a reachable TURN relay.',
        timeout,
      );
    } catch (_) {
      await closeSession(peerId);
      rethrow;
    }
  }

  Future<void> sendText(String peerId, String text) async {
    final channel = _sessions[peerId]?.channel;
    if (channel == null) throw StateError('No data channel for $peerId');
    await channel.send(RTCDataChannelMessage(text));
  }

  Future<void> sendBinary(String peerId, Uint8List bytes) async {
    final channel = _sessions[peerId]?.channel;
    if (channel == null) throw StateError('No data channel for $peerId');
    await channel.send(RTCDataChannelMessage.fromBinary(bytes));
  }

  int bufferedAmount(String peerId) =>
      _sessions[peerId]?.channel?.bufferedAmount ?? 0;

  bool hasSession(String peerId) => _sessions.containsKey(peerId);

  Future<_PeerSession> _ensureSession(
    String peerId, {
    required bool initiator,
  }) async {
    final existing = _sessions[peerId];
    if (existing != null) {
      if (initiator) await _startOffer(existing);
      return existing;
    }
    final pending = _creatingSessions[peerId];
    if (pending != null) {
      final session = await pending;
      if (initiator) await _startOffer(session);
      return session;
    }
    final creating = _createSession(peerId);
    _creatingSessions[peerId] = creating;
    late final _PeerSession session;
    try {
      session = await creating;
    } finally {
      _creatingSessions.remove(peerId);
    }
    if (initiator) await _startOffer(session);
    return session;
  }

  Future<_PeerSession> _createSession(String peerId) async {
    final config = <String, dynamic>{
      // On an isolated LAN, gather local host candidates without contacting
      // public STUN services. The signaling relay remains local as well.
      'iceServers': signaling.usesLocalEndpoint
          ? <Map<String, dynamic>>[]
          : await AppConfig.iceServers(),
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };

    final pc = await createPeerConnection(config);
    final session = _PeerSession(peerId: peerId, pc: pc);
    _sessions[peerId] = session;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      signaling.sendSignal(peerId, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onIceConnectionState = (state) {
      debugPrint('WebRTC ICE state ($peerId): $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _failSession(
          session,
          'ICE negotiation failed. A TURN relay may be required for these networks.',
        );
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        unawaited(_publishSelectedRoute(session));
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('WebRTC peer state ($peerId): $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _failSession(
          session,
          'Peer connection failed. Check the TURN relay and network firewall.',
        );
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _teardown(peerId);
      }
    };

    pc.onDataChannel = (channel) => _bindChannel(session, channel);

    return session;
  }

  Future<void> _startOffer(_PeerSession session) async {
    if (session.offerStarted || session.remoteDescriptionSet) return;
    session.offerStarted = true;
    session.makingOffer = true;
    try {
      final dc = await session.pc.createDataChannel(
        'yonfile',
        RTCDataChannelInit()..ordered = true,
      );
      _bindChannel(session, dc);

      final offer = await session.pc.createOffer();
      await session.pc.setLocalDescription(offer);
      final local = await session.pc.getLocalDescription();
      signaling.sendSignal(session.peerId, {
        'type': 'offer',
        'sdp': local?.sdp ?? offer.sdp,
        'sdpType': local?.type ?? offer.type,
      });
    } catch (_) {
      session.offerStarted = false;
      rethrow;
    } finally {
      session.makingOffer = false;
    }
  }

  void _bindChannel(_PeerSession session, RTCDataChannel channel) {
    session.channel = channel;

    channel.onDataChannelState = (state) {
      if (!_stateController.isClosed) {
        _stateController.add(PeerChannelState(session.peerId, state));
      }
      if (state == RTCDataChannelState.RTCDataChannelOpen &&
          !session.openCompleter.isCompleted) {
        session.openCompleter.complete(channel);
        unawaited(_publishSelectedRoute(session));
      }
    };

    channel.onMessage = (message) {
      if (!_messageController.isClosed) {
        _messageController.add(PeerMessage(session.peerId, message));
      }
    };

    // A remote-created channel can already be open by the time it is bound.
    // Publish its current state so the home screen can leave Radar immediately.
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      if (!session.openCompleter.isCompleted) {
        session.openCompleter.complete(channel);
      }
      unawaited(_publishSelectedRoute(session));
      if (!_stateController.isClosed) {
        _stateController.add(
          PeerChannelState(
            session.peerId,
            RTCDataChannelState.RTCDataChannelOpen,
          ),
        );
      }
    }
  }

  Future<void> _publishSelectedRoute(_PeerSession session) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      if (!identical(_sessions[session.peerId], session)) return;
      try {
        final reports = await session.pc.getStats();
        final pairs = reports.where((report) => report.type == 'candidate-pair');
        final transports = reports.where((report) => report.type == 'transport');
        final selectedIds = transports
            .map((report) => report.values['selectedCandidatePairId'])
            .whereType<String>()
            .toSet();
        StatsReport? selectedPair;
        for (final pair in pairs) {
          final values = pair.values;
          if (selectedIds.contains(pair.id) ||
              values['selected'] == true ||
              (values['nominated'] == true && values['state'] == 'succeeded')) {
            selectedPair = pair;
            break;
          }
        }
        if (selectedPair != null) {
          final localId = selectedPair.values['localCandidateId'];
          final remoteId = selectedPair.values['remoteCandidateId'];
          final candidateTypes = reports
              .where((report) =>
                  (report.type == 'local-candidate' ||
                      report.type == 'remote-candidate') &&
                  (report.id == localId || report.id == remoteId))
              .map((report) => report.values['candidateType'])
              .whereType<String>()
              .toSet();
          final route = candidateTypes.contains('relay')
              ? 'relay'
              : candidateTypes.any(
                  (type) =>
                      type == 'host' || type == 'srflx' || type == 'prflx',
                )
              ? 'direct'
              : null;
          if (route != null) {
            if (!_routeController.isClosed) {
              _routeController.add(PeerRouteState(session.peerId, route));
            }
            return;
          }
        }
      } catch (error) {
        debugPrint('Unable to read selected ICE route (${session.peerId}): $error');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (identical(_sessions[session.peerId], session) &&
        !_routeController.isClosed) {
      _routeController.add(PeerRouteState(session.peerId, 'unknown'));
    }
  }

  Future<void> _onSignal(SignalEvent event) async {
    final type = event.payload['type'] as String?;
    try {
      switch (type) {
        case 'offer':
          await _handleOffer(event);
          break;
        case 'answer':
          await _handleAnswer(event);
          break;
        case 'candidate':
          await _handleCandidate(event);
          break;
        case 'disconnect':
          await closeSession(event.senderId);
          if (!_disconnectController.isClosed) {
            _disconnectController.add(event.senderId);
          }
          break;
      }
    } catch (error) {
      debugPrint('Signal handling error ($type): $error');
    }
  }

  Future<void> _handleOffer(SignalEvent event) async {
    final session = await _ensureSession(event.senderId, initiator: false);
    final collision =
        session.makingOffer ||
        await session.pc.getSignalingState() !=
            RTCSignalingState.RTCSignalingStateStable;
    final localId = signaling.peerId;
    final polite = localId != null && localId.compareTo(event.senderId) > 0;
    session.ignoreOffer = !polite && collision;
    if (session.ignoreOffer) {
      debugPrint('Ignoring colliding offer from ${event.senderId}');
      return;
    }
    if (collision) {
      await session.pc.setLocalDescription(
        RTCSessionDescription('', 'rollback'),
      );
      session.remoteDescriptionSet = false;
      session.channel?.close();
      session.channel = null;
    }
    await session.pc.setRemoteDescription(
      RTCSessionDescription(
        event.payload['sdp'] as String?,
        event.payload['sdpType'] as String?,
      ),
    );
    session.remoteDescriptionSet = true;
    await _flushCandidates(session);

    final answer = await session.pc.createAnswer();
    await session.pc.setLocalDescription(answer);
    final local = await session.pc.getLocalDescription();
    signaling.sendSignal(event.senderId, {
      'type': 'answer',
      'sdp': local?.sdp ?? answer.sdp,
      'sdpType': local?.type ?? answer.type,
    });
  }

  Future<void> _handleAnswer(SignalEvent event) async {
    final session = _sessions[event.senderId];
    if (session == null) return;
    await session.pc.setRemoteDescription(
      RTCSessionDescription(
        event.payload['sdp'] as String?,
        event.payload['sdpType'] as String?,
      ),
    );
    session.remoteDescriptionSet = true;
    session.ignoreOffer = false;
    await _flushCandidates(session);
  }

  Future<void> _handleCandidate(SignalEvent event) async {
    final session = await _ensureSession(event.senderId, initiator: false);
    if (session.ignoreOffer) return;
    final candidate = RTCIceCandidate(
      event.payload['candidate'] as String?,
      event.payload['sdpMid'] as String?,
      event.payload['sdpMLineIndex'] as int?,
    );
    if (!session.remoteDescriptionSet) {
      session.pendingCandidates.add(candidate);
    } else {
      await session.pc.addCandidate(candidate);
    }
  }

  Future<void> _flushCandidates(_PeerSession session) async {
    for (final candidate in session.pendingCandidates) {
      await session.pc.addCandidate(candidate);
    }
    session.pendingCandidates.clear();
  }

  Future<void> closeSession(String peerId) async {
    await _sessions[peerId]?.pc.close();
    _teardown(peerId);
  }

  void _failSession(_PeerSession session, String reason) {
    if (!session.failureCompleter.isCompleted) {
      session.failureCompleter.complete(reason);
    }
    if (identical(_sessions[session.peerId], session)) {
      unawaited(session.pc.close());
      _teardown(session.peerId);
    }
  }

  /// Closes the local session and asks the remote peer to leave this pairing.
  Future<void> disconnectPeer(String peerId) async {
    signaling.sendSignal(peerId, const {'type': 'disconnect'});
    await closeSession(peerId);
  }

  void _teardown(String peerId) {
    _sessions.remove(peerId);
    if (!_routeController.isClosed) {
      _routeController.add(PeerRouteState(peerId, 'unknown'));
    }
    if (!_stateController.isClosed) {
      _stateController.add(
        PeerChannelState(peerId, RTCDataChannelState.RTCDataChannelClosed),
      );
    }
  }

  void dispose() {
    _signalSub?.cancel();
    for (final session in _sessions.values) {
      session.pc.close();
    }
    _sessions.clear();
    _messageController.close();
    _stateController.close();
    _routeController.close();
    _disconnectController.close();
  }
}
