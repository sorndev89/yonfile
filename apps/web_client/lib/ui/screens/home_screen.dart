import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/yon_theme.dart';
import '../../models/file_transfer_state.dart';
import '../../models/peer_device.dart';
import '../../models/picked_file.dart';
import '../../services/file_chunker_service.dart';
import '../../services/local_signaling_host.dart';
import '../../services/signaling_service.dart';
import '../../services/webrtc_service.dart';
import '../widgets/peer_avatar.dart';
import '../widgets/pin_room_card.dart';
import '../widgets/radar_canvas.dart';
import '../widgets/transfer_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onToggleTheme,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SignalingService _signaling;
  late final WebRtcService _webrtc;
  final LocalSignalingHost _localHost = LocalSignalingHost();
  late final String _onlineSignalingUrl;
  final FileChunkerService _chunker = FileChunkerService();
  final math.Random _random = math.Random.secure();

  final List<StreamSubscription<dynamic>> _subs = [];

  SignalingStatus _status = SignalingStatus.disconnected;
  String? _peerId;

  final Map<String, PeerDevice> _lanPeers = {};
  final Map<String, PeerDevice> _pinPeers = {};

  String _myName = 'ອຸປະກອນຂອງຂ້ອຍ';
  PeerDeviceType _myDeviceType = PeerDeviceType.desktop;
  bool _deviceTypeResolved = false;
  bool _draggingOver = false;
  bool _localHostRunning = false;
  bool _usingLocalSignaling = false;

  String _ownPin = _randomPin();
  String? _joinedPin;

  final List<FileTransferState> _transfers = [];
  final ValueNotifier<int> _transferRevision = ValueNotifier(0);
  final Map<String, Uint8List> _outgoingBytes = {};
  final Map<String, Completer<bool>> _pendingAccepts = {};
  final Map<String, IncomingFile> _incoming = {};
  final Map<String, String> _activeIncomingId = {};
  final Map<String, String> _transferPeers = {};
  final Set<String> _cancelled = {};
  final Set<String> _connectedPeerIds = {};

  int get _incomingReservedBytes =>
      _incoming.values.fold(0, (total, file) => total + file.fileSize);

  @override
  void initState() {
    super.initState();
    _onlineSignalingUrl = AppConfig.signalingUrl;
    _signaling = SignalingService()..joinPin(_ownPin);
    _webrtc = WebRtcService(_signaling);
    _loadPrefs();
    _bindStreams();
    _signaling.connect();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('device_name');
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _myName = saved);
    }
    // Cache the saved name even if the WebSocket has not registered yet.
    _signaling.register(_myName, _myDeviceType);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_deviceTypeResolved) return;
    _deviceTypeResolved = true;
    _myDeviceType = _detectDeviceType();
    _signaling.register(_myName, _myDeviceType);
  }

  PeerDeviceType _detectDeviceType() {
    final size = MediaQuery.sizeOf(context);
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux) {
      if (size.width < 600) return PeerDeviceType.mobile;
      if (size.width < 1100) return PeerDeviceType.tablet;
      return PeerDeviceType.desktop;
    }
    return size.shortestSide < 600
        ? PeerDeviceType.mobile
        : PeerDeviceType.tablet;
  }

  void _bindStreams() {
    _subs.add(
      _signaling.statusStream.listen((status) {
        if (!mounted) return;
        setState(() {
          _status = status;
          if (status == SignalingStatus.disconnected) {
            _peerId = null;
            _lanPeers.clear();
            _pinPeers.clear();
          }
        });
      }),
    );

    _subs.add(
      _signaling.registeredStream.listen((id) {
        if (!mounted) return;
        setState(() => _peerId = id);
      }),
    );

    _subs.add(
      _signaling.errorStream.listen((code) {
        if (!mounted) return;
        if (code == 'pin_rate_limited') {
          _snack('ລອງເຂົ້າຫ້ອງຫຼາຍເກີນໄປ ກະລຸນາລໍຖ້າ 1 ນາທີ');
        } else if (code == 'invalid_pin') {
          _snack('ລະຫັດ PIN ບໍ່ຖືກຕ້ອງ');
        }
      }),
    );

    _subs.add(
      _signaling.peersStream.listen((event) {
        if (!mounted) return;
        setState(() {
          if (event.scope == PeerScope.lan) {
            _lanPeers
              ..clear()
              ..addEntries(
                event.peers
                    .where((p) => p.id != _peerId)
                    .map((p) => MapEntry(p.id, p)),
              );
          } else {
            // Ignore delayed updates from a PIN room the user has already left.
            if (event.pin != _ownPin) return;
            _pinPeers
              ..clear()
              ..addEntries(
                event.peers
                    .where((p) => p.id != _peerId)
                    .map((p) => MapEntry(p.id, p)),
              );
          }
        });
      }),
    );

    _subs.add(_webrtc.messages.listen(_onPeerMessage));
    _subs.add(
      _webrtc.channelStates.listen((event) {
        if (!mounted) return;
        setState(() {
          if (event.isOpen) {
            _connectedPeerIds.add(event.peerId);
          } else {
            _connectedPeerIds.remove(event.peerId);
          }
        });
      }),
    );
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _webrtc.dispose();
    _signaling.dispose();
    _localHost.stop();
    _transferRevision.dispose();
    super.dispose();
  }

  /* ------------------------------- Peers ------------------------------- */

  List<PeerDevice> get _peers {
    final merged = <String, PeerDevice>{};
    for (final p in _lanPeers.values) {
      merged[p.id] = p;
    }
    for (final p in _pinPeers.values) {
      merged[p.id] = p;
    }
    return merged.values.toList();
  }

  String _peerName(String peerId) {
    for (final p in _peers) {
      if (p.id == peerId) return p.name;
    }
    return 'YonFile';
  }

  PeerDevice get _selfDevice => PeerDevice(
    id: _peerId ?? 'self',
    name: _myName,
    deviceType: _myDeviceType,
    scope: PeerScope.lan,
  );

  /* --------------------------- File sending ---------------------------- */

  Future<void> _pickAndSend(PeerDevice peer) async {
    if (!await _ensurePinAccess(peer)) return;
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final picked = <PickedFile>[];
      var totalBytes = 0;
      for (final f in files) {
        final knownSize = await f.length();
        if (knownSize != null &&
            totalBytes + knownSize > AppConfig.maxFileSizeBytes) {
          _snack('ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ 512 MB');
          return;
        }
        final bytes = await f.readAsBytes();
        if (totalBytes + bytes.length > AppConfig.maxFileSizeBytes) {
          _snack('ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ 512 MB');
          return;
        }
        totalBytes += bytes.length;
        picked.add(
          PickedFile(
            name: f.name,
            size: bytes.length,
            bytes: bytes,
            mimeType: _guessMime(f.name),
          ),
        );
      }
      await _sendFiles(peer, picked);
    } catch (error) {
      _snack('ເລືອກໄຟລ໌ບໍ່ສຳເລັດ: $error');
    }
  }

  Future<void> _sendDroppedFiles(
    List<PickedFile> files,
    PeerDevice? target,
  ) async {
    if (files.isEmpty) return;
    if (_peers.isEmpty) {
      _snack('ຍັງບໍ່ມີອຸປະກອນໃນເຄືອຂ່າຍ');
      return;
    }
    var peer = target;
    if (peer == null) {
      if (_peers.length == 1) {
        peer = _peers.first;
      } else {
        peer = await _choosePeerDialog();
        if (peer == null) return;
      }
    }
    await _sendFiles(peer, files);
  }

  Future<void> _sendFiles(PeerDevice peer, List<PickedFile> files) async {
    if (files.fold<int>(0, (sum, file) => sum + file.size) >
        AppConfig.maxFileSizeBytes) {
      _snack('ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ 512 MB');
      return;
    }
    if (!await _ensurePinAccess(peer)) return;
    try {
      if (!_webrtc.isOpen(peer.id)) {
        await _webrtc.connect(peer.id);
        await _webrtc.waitUntilOpen(peer.id);
      }
    } catch (error) {
      await _webrtc.closeSession(peer.id);
      _snack('ເຊື່ອມຕໍ່ກັບ ${peer.name} ບໍ່ສຳເລັດ ກະລຸນາລອງໃໝ່');
      debugPrint('connect error: $error');
      return;
    }
    _openTransferSheet();
    for (final file in files) {
      await _sendSingleFile(peer, file);
    }
  }

  Future<bool> _ensurePinAccess(PeerDevice peer) async {
    if (peer.scope == PeerScope.pin || _pinPeers.containsKey(peer.id)) {
      return true;
    }

    var enteredPin = '';
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('ໃສ່ PIN ຂອງ ${peer.name}'),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              hintText: 'PIN 6 ໂຕເລກ',
              counterText: '',
            ),
            onChanged: (value) =>
                setDialogState(() => enteredPin = value.trim()),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ຍົກເລີກ'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, enteredPin),
              child: const Text('ຢືນຢັນ'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pin == null) return false;
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      _snack('PIN ຕ້ອງມີ 6 ໂຕເລກ');
      return false;
    }

    if (!_signaling.isConnected) {
      _snack('ຍັງບໍ່ເຊື່ອມຕໍ່ server ຈຶ່ງກວດ PIN ບໍ່ໄດ້');
      return false;
    }

    _joinPin(pin);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_ownPin == pin && _pinPeers.containsKey(peer.id)) {
        _snack('PIN ຖືກຕ້ອງ ແລະ ${peer.name} ຢູ່ໃນຫ້ອງນີ້');
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted) {
      _snack('PIN ບໍ່ຖືກຕ້ອງ ຫຼື ${peer.name} ບໍ່ໄດ້ເຂົ້າຫ້ອງ PIN ນີ້');
    }
    return false;
  }

  Future<void> _sendSingleFile(PeerDevice peer, PickedFile file) async {
    final id = _generateId();
    final completer = Completer<bool>();
    _pendingAccepts[id] = completer;
    _outgoingBytes[id] = file.bytes;
    _transferPeers[id] = peer.id;

    _upsertTransfer(
      FileTransferState(
        id: id,
        fileName: file.name,
        fileSize: file.size,
        direction: TransferDirection.send,
        peerName: peer.name,
        status: TransferStatus.awaitingAccept,
        startedAt: DateTime.now(),
      ),
    );

    try {
      await _webrtc.sendText(
        peer.id,
        jsonEncode({
          'type': 'offer-file',
          'id': id,
          'name': file.name,
          'size': file.size,
          'mime': file.mimeType,
        }),
      );

      final accepted = await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => false,
      );

      if (!accepted) {
        _updateTransfer(
          id,
          (t) => t.copyWith(status: TransferStatus.cancelled),
        );
        return;
      }

      final sha = _chunker.sha256Of(file.bytes);
      _updateTransfer(
        id,
        (t) => t.copyWith(status: TransferStatus.transferring, sha256: sha),
      );

      final stopwatch = Stopwatch()..start();
      await _chunker.sendFile(
        bytes: file.bytes,
        sendChunk: (chunk) => _webrtc.sendBinary(peer.id, chunk),
        bufferedAmount: () => _webrtc.bufferedAmount(peer.id),
        onProgress: (sent) {
          final seconds = stopwatch.elapsedMilliseconds / 1000.0;
          _updateTransfer(
            id,
            (t) => t.copyWith(
              transferred: sent,
              bytesPerSecond: seconds > 0.2 ? sent / seconds : 0,
            ),
          );
        },
        isCancelled: () => _cancelled.contains(id),
      );

      await _webrtc.sendText(
        peer.id,
        jsonEncode({'type': 'eof', 'id': id, 'sha256': sha}),
      );
      _updateTransfer(
        id,
        (t) => t.copyWith(
          status: TransferStatus.verifying,
          transferred: file.size,
        ),
      );
    } on TransferCancelledException {
      _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
      await _webrtc.sendText(
        peer.id,
        jsonEncode({'type': 'cancel-file', 'id': id}),
      );
    } catch (error) {
      _updateTransfer(
        id,
        (t) => t.copyWith(status: TransferStatus.failed, error: '$error'),
      );
    } finally {
      _outgoingBytes.remove(id);
      _transferPeers.remove(id);
      _cancelled.remove(id);
      _pendingAccepts.remove(id);
    }
  }

  /* -------------------------- Message handling ------------------------- */

  void _onPeerMessage(PeerMessage message) {
    if (message.isBinary) {
      _onBinary(message.peerId, message.binary);
      return;
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (data['type']) {
      case 'offer-file':
        _onOfferFile(message.peerId, data);
        break;
      case 'accept-file':
        final acceptId = data['id'];
        if (acceptId is String &&
            _pendingAccepts[acceptId]?.isCompleted == false) {
          _pendingAccepts[acceptId]!.complete(true);
        }
        break;
      case 'reject-file':
        final rejectId = data['id'];
        if (rejectId is String &&
            _pendingAccepts[rejectId]?.isCompleted == false) {
          _pendingAccepts[rejectId]!.complete(false);
        }
        break;
      case 'eof':
        _onEof(message.peerId, data);
        break;
      case 'transfer-complete':
        _onTransferComplete(data);
        break;
      case 'cancel-file':
        _onRemoteCancel(data);
        break;
      case 'text':
        if (data['text'] is String) {
          _showIncomingText(message.peerId, data['text'] as String);
        }
        break;
    }
  }

  void _onBinary(String peerId, Uint8List bytes) {
    final id = _activeIncomingId[peerId];
    if (id == null) return;
    final incoming = _incoming[id];
    if (incoming == null) return;
    if (bytes.isEmpty || incoming.received + bytes.length > incoming.fileSize) {
      _incoming.remove(id);
      _activeIncomingId.remove(peerId);
      _transferPeers.remove(id);
      _updateTransfer(
        id,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          error: 'ຂໍ້ມູນໄຟລ໌ເກີນຂະໜາດທີ່ແຈ້ງ',
        ),
      );
      _webrtc.sendText(peerId, jsonEncode({'type': 'cancel-file', 'id': id}));
      return;
    }
    incoming.addChunk(bytes);
    _updateTransfer(
      id,
      (t) => t.copyWith(
        transferred: incoming.received,
        bytesPerSecond: incoming.bytesPerSecond,
      ),
    );
  }

  Future<void> _onOfferFile(String peerId, Map<String, dynamic> data) async {
    if (!mounted) return;
    final id = data['id'] is String ? data['id'] as String : '';
    final incomingName = data['name'] is String
        ? data['name'] as String
        : 'file';
    final name = incomingName
        .replaceAll(RegExp(r'[\\/\u0000-\u001f]'), '_')
        .trim();
    final size = data['size'] is num ? (data['size'] as num).toInt() : -1;
    final peerName = _peerName(peerId);

    if (id.isEmpty ||
        name.isEmpty ||
        size < 0 ||
        size > AppConfig.maxFileSizeBytes ||
        _incomingReservedBytes + size > AppConfig.maxFileSizeBytes ||
        _activeIncomingId.containsKey(peerId)) {
      await _webrtc.sendText(
        peerId,
        jsonEncode({'type': 'reject-file', 'id': id}),
      );
      return;
    }

    final accepted = await _confirmReceive(peerName, name, size);
    if (!accepted) {
      await _webrtc.sendText(
        peerId,
        jsonEncode({'type': 'reject-file', 'id': id}),
      );
      return;
    }

    _incoming[id] = IncomingFile(id: id, fileName: name, fileSize: size);
    _activeIncomingId[peerId] = id;
    _transferPeers[id] = peerId;
    _upsertTransfer(
      FileTransferState(
        id: id,
        fileName: name,
        fileSize: size,
        direction: TransferDirection.receive,
        peerName: peerName,
        status: TransferStatus.transferring,
        startedAt: DateTime.now(),
      ),
    );
    await _webrtc.sendText(
      peerId,
      jsonEncode({'type': 'accept-file', 'id': id}),
    );
  }

  Future<void> _onEof(String peerId, Map<String, dynamic> data) async {
    final id = data['id'] is String ? data['id'] as String : '';
    if (id.isEmpty) return;
    final incoming = _incoming[id];
    if (incoming == null) return;

    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.verifying));
    final expected = data['sha256'] is String ? data['sha256'] as String : null;
    final actual = sha256Hex(incoming.takeBytes());
    final verified =
        incoming.received == incoming.fileSize &&
        expected != null &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(expected) &&
        expected == actual;

    final bytes = incoming.takeBytes();
    Uri? savedFile;
    var saveCompleted = false;
    try {
      if (verified) {
        savedFile = await FilePicker.saveFile(
          fileName: incoming.fileName,
          bytes: bytes,
        );
        // On web, FilePicker starts a browser download and intentionally
        // returns null because the browser does not expose a filesystem URI.
        saveCompleted = true;
      }
    } catch (error) {
      debugPrint('save error: $error');
    }
    final completed =
        verified && saveCompleted && (kIsWeb || savedFile != null);

    await _webrtc.sendText(
      peerId,
      jsonEncode({
        'type': 'transfer-complete',
        'id': id,
        'verified': completed,
      }),
    );

    _updateTransfer(
      id,
      (t) => t.copyWith(
        status: completed ? TransferStatus.completed : TransferStatus.failed,
        verified: completed,
        transferred: incoming.fileSize,
        error: completed
            ? null
            : !verified
            ? 'ຂະໜາດໄຟລ໌ ຫຼື SHA-256 ບໍ່ກົງກັນ'
            : 'ບັນທຶກໄຟລ໌ບໍ່ສຳເລັດ ຫຼືຖືກຍົກເລີກ',
      ),
    );
    _incoming.remove(id);
    _activeIncomingId.remove(peerId);
    _transferPeers.remove(id);
  }

  void _onTransferComplete(Map<String, dynamic> data) {
    final id = data['id'] is String ? data['id'] as String : '';
    if (id.isEmpty) return;
    final verified = data['verified'] as bool? ?? true;
    _updateTransfer(
      id,
      (t) => t.copyWith(
        status: verified ? TransferStatus.completed : TransferStatus.failed,
        verified: verified,
        error: verified ? null : 'ປາຍທາງກວດສອບບໍ່ຜ່ານ',
      ),
    );
  }

  void _onRemoteCancel(Map<String, dynamic> data) {
    final id = data['id'] is String ? data['id'] as String : '';
    if (id.isEmpty) return;
    if (_outgoingBytes.containsKey(id)) _cancelled.add(id);
    final pending = _pendingAccepts[id];
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final peerId = _transferPeers.remove(id);
    _incoming.remove(id);
    if (peerId != null && _activeIncomingId[peerId] == id) {
      _activeIncomingId.remove(peerId);
    }
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
  }

  /* ------------------------------- Actions ----------------------------- */

  void _cancelTransfer(String id) {
    final index = _transfers.indexWhere((t) => t.id == id);
    if (index < 0) return;
    final transfer = _transfers[index];
    if (!transfer.isActive) return;
    _cancelled.add(id);
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
    _pendingAccepts[id]?.complete(false);
    final peerId = _transferPeers[id];
    if (peerId != null) {
      _webrtc.sendText(peerId, jsonEncode({'type': 'cancel-file', 'id': id}));
      final isIncoming = _incoming.remove(id) != null;
      if (isIncoming) _cancelled.remove(id);
      if (_activeIncomingId[peerId] == id) _activeIncomingId.remove(peerId);
    }
  }

  void _joinPin(String pin) {
    _signaling.joinPin(pin);
    setState(() {
      _joinedPin = pin;
      _ownPin = pin;
      _pinPeers.clear();
    });
    _snack('ກຳລັງເຂົ້າຫ້ອງ PIN');
  }

  void _leavePin() {
    _signaling.leavePin();
    final nextPin = _randomPin();
    _signaling.joinPin(nextPin);
    setState(() {
      _joinedPin = null;
      _pinPeers.clear();
      _ownPin = nextPin;
    });
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _myName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ຕັ້ງຊື່ອຸປະກອນ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ເຊັ່ນ: iPhone ຂອງຂ້ອຍ'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ຍົກເລີກ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('ບັນທຶກ'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final name = result.trim();
    if (name.isEmpty) return;
    setState(() => _myName = name);
    _signaling.updateName(name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
  }

  Future<void> _sendTextMessage(PeerDevice peer) async {
    try {
      if (!_webrtc.isOpen(peer.id)) {
        await _webrtc.connect(peer.id);
        await _webrtc.waitUntilOpen(peer.id);
      }
    } catch (_) {
      _snack('ເຊື່ອມຕໍ່ກັບ ${peer.name} ບໍ່ສຳເລັດ');
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ສົ່ງຂໍ້ຄວາມຫາ ${peer.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'ພິມຂໍ້ຄວາມ...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ຍົກເລີກ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('ສົ່ງ'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    await _webrtc.sendText(
      peer.id,
      jsonEncode({'type': 'text', 'text': text.trim()}),
    );
    _snack('ສົ່ງແລ້ວ');
  }

  Future<void> _openScanner() async {
    final pin = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScannerPage()));
    if (pin != null && pin.length == 6) _joinPin(pin);
  }

  void _openTransferSheet() {
    if (!mounted) return;
    TransferSheet.show(
      context,
      transfers: _transfers,
      revision: _transferRevision,
      onCancel: _cancelTransfer,
      onClearCompleted: () {
        setState(() => _transfers.removeWhere((t) => !t.isActive));
        _transferRevision.value++;
        Navigator.pop(context);
      },
    );
  }

  /* ------------------------------- Helpers ----------------------------- */

  Future<bool> _confirmReceive(
    String peerName,
    String fileName,
    int size,
  ) async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('ມີໄຟລ໌ເຂົ້າມາ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$peerName ຕ້ອງການສົ່ງໄຟລ໌ມາໃຫ້ທ່ານ:'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.insert_drive_file_rounded,
                  color: YonTheme.yonOrange,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              FileTransferState.formatBytes(size),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'ປະຕິເສດ',
              style: TextStyle(color: YonTheme.roseRed),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ຍອມຮັບ'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<PeerDevice?> _choosePeerDialog() async {
    if (!mounted) return null;
    return showDialog<PeerDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('ເລືອກອຸປະກອນປາຍທາງ'),
        children: _peers
            .map(
              (peer) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, peer),
                child: Row(
                  children: [
                    Icon(peer.icon, color: YonTheme.yonOrange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(peer.name)),
                    Text(
                      peer.typeLabel,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  void _showIncomingText(String peerId, String text) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ຂໍ້ຄວາມຈາກ ${_peerName(peerId)}'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ປິດ'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _upsertTransfer(FileTransferState transfer) {
    if (!mounted) return;
    final index = _transfers.indexWhere((t) => t.id == transfer.id);
    setState(() {
      if (index >= 0) {
        _transfers[index] = transfer;
      } else {
        _transfers.insert(0, transfer);
      }
    });
    _transferRevision.value++;
  }

  void _updateTransfer(
    String id,
    FileTransferState Function(FileTransferState) update,
  ) {
    if (!mounted) return;
    final index = _transfers.indexWhere((t) => t.id == id);
    if (index < 0) return;
    setState(() => _transfers[index] = update(_transfers[index]));
    _transferRevision.value++;
  }

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(9999)}';

  static String _randomPin() {
    final random = math.Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buffer.write(random.nextInt(10));
    }
    return buffer.toString();
  }

  String _guessMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  String sha256Hex(Uint8List bytes) => _chunker.sha256Of(bytes);

  Future<void> _showOfflineOptions() async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ໃຊ້ງານ offline ໃນ LAN'),
        content: Text(
          _localHostRunning
              ? 'ກຳລັງເປີດ local host. ໃຫ້ອຸປະກອນອື່ນເຊື່ອມຕໍ່ IP ເຄື່ອງນີ້ທີ່ພອດ 3001.'
              : 'ຕໍ່ອຸປະກອນໃນ Wi-Fi/LAN ດຽວກັນໄດ້ ເຖິງແມ່ນບໍ່ມີ Internet ຫຼື server ກາງ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ປິດ'),
          ),
          if (_usingLocalSignaling)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'online'),
              child: const Text('ກັບໄປໂໝດອອນລາຍ'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'join'),
            child: const Text('ເຂົ້າດ້ວຍ IP'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'host'),
            child: Text(
              _localHostRunning ? 'ສະແດງ IP' : 'ເປີດ host ໃນເຄື່ອງນີ້',
            ),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'host') {
      await _startLocalHost();
    } else if (action == 'join') {
      await _joinLocalHost();
    } else if (action == 'online') {
      await _returnOnline();
    }
  }

  Future<void> _startLocalHost() async {
    try {
      final addresses = await _localHost.start();
      if (!mounted) return;
      if (addresses.isEmpty) {
        _snack('ບໍ່ພົບ IP ຂອງ LAN. ກວດສອບ Wi-Fi ແລ້ວລອງອີກຄັ້ງ');
        await _localHost.stop();
        return;
      }
      await _signaling.useEndpoint('ws://127.0.0.1:3001/ws');
      if (!mounted) return;
      setState(() {
        _localHostRunning = true;
        _usingLocalSignaling = true;
      });
      _snack(
        'Offline host ພ້ອມແລ້ວ: '
        '${addresses.map((address) => '$address:3001').join(', ')}',
      );
    } catch (error) {
      _snack('ເປີດ offline host ບໍ່ສຳເລັດ: $error');
    }
  }

  Future<void> _joinLocalHost() async {
    final controller = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ເຂົ້າຫາ offline host'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'IP ຂອງເຄື່ອງ host',
            hintText: 'ຕົວຢ່າງ 192.168.1.20',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ຍົກເລີກ'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('ເຊື່ອມຕໍ່'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || address == null || address.isEmpty) return;
    final host = address
        .replaceFirst(RegExp(r'^ws://'), '')
        .replaceFirst(RegExp(r'/ws$'), '')
        .replaceFirst(RegExp(r':\d+$'), '');
    try {
      await _signaling.useEndpoint('ws://$host:3001/ws');
      if (!mounted) return;
      setState(() => _usingLocalSignaling = true);
      _snack('ກຳລັງເຊື່ອມຫາ offline host $host');
    } catch (error) {
      _snack('ເຊື່ອມຫາ offline host ບໍ່ສຳເລັດ: $error');
    }
  }

  Future<void> _returnOnline() async {
    await _localHost.stop();
    await _signaling.useEndpoint(_onlineSignalingUrl);
    if (!mounted) return;
    setState(() {
      _localHostRunning = false;
      _usingLocalSignaling = false;
    });
  }

  /* -------------------------------- Build ------------------------------ */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            return isWide ? _buildDesktop(constraints) : _buildMobile();
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final connected = _status == SignalingStatus.connected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 6),
      child: Row(
        children: [
          Image.asset(
            'assets/branding/yonfile-mark.png',
            width: 28,
            height: 28,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              children: [
                const TextSpan(text: 'Yon'),
                TextSpan(
                  text: 'File',
                  style: TextStyle(color: YonTheme.yonOrange),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? YonTheme.emeraldGreen : YonTheme.amberGold,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: _usingLocalSignaling
                ? 'ໃຊ້ signaling server ອອນລາຍ'
                : 'ຕັ້ງຄ່າໃຊ້ງານ offline ໃນ LAN',
            onPressed: _showOfflineOptions,
            icon: Icon(
              _usingLocalSignaling
                  ? Icons.wifi_tethering_rounded
                  : Icons.wifi_tethering_off_rounded,
              color: _usingLocalSignaling ? YonTheme.yonOrange : null,
            ),
          ),
          if (_transfers.any((t) => t.isActive))
            _BadgeIconButton(
              icon: Icons.swap_vert_rounded,
              count: _transfers.where((t) => t.isActive).length,
              onTap: _openTransferSheet,
            ),
          IconButton(
            tooltip: 'ແຈ້ງເຕືອນ',
            onPressed: _openTransferSheet,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'ປ່ຽນໂໝດສີ',
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile() {
    return Column(
      children: [
        _buildTopBar(),
        _buildDeviceNameRow(),
        Expanded(child: _buildRadarArea()),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showPinSheet(),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('ໃສ່ລະຫັດຂ້າມເນັດ'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openTransferSheet,
                  icon: const Icon(Icons.folder_rounded),
                  label: const Text('ປະຫວັດ'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktop(BoxConstraints constraints) {
    return Column(
      children: [
        _buildTopBar(),
        _buildDeviceNameRow(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildRadarArea()),
              SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 16, 16),
                  child: ListView(
                    children: [
                      PinRoomCard(
                        ownPin: _ownPin,
                        joinedPin: _joinedPin,
                        onJoinPin: _joinPin,
                        onLeavePin: _leavePin,
                        onScan: _openScanner,
                      ),
                      const SizedBox(height: 16),
                      _buildTransferPanel(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceNameRow() {
    return InkWell(
      onTap: _editName,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Row(
          children: [
            Icon(_selfDevice.icon, size: 16, color: YonTheme.yonOrange),
            const SizedBox(width: 6),
            Text(
              'ຊື່ເຄື່ອງ: $_myName',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_rounded, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarArea() {
    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingOver = true),
      onDragExited: (_) => setState(() => _draggingOver = false),
      onDragDone: (details) async {
        setState(() => _draggingOver = false);
        final picked = <PickedFile>[];
        var totalBytes = 0;
        for (final item in details.files) {
          final knownSize = await item.length();
          if (totalBytes + knownSize > AppConfig.maxFileSizeBytes) {
            _snack('ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ 512 MB');
            return;
          }
          final bytes = await item.readAsBytes();
          if (totalBytes + bytes.length > AppConfig.maxFileSizeBytes) {
            _snack('ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ 512 MB');
            return;
          }
          totalBytes += bytes.length;
          picked.add(
            PickedFile(
              name: item.name,
              size: bytes.length,
              bytes: bytes,
              mimeType: _guessMime(item.name),
            ),
          );
        }
        await _sendDroppedFiles(picked, null);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _draggingOver ? YonTheme.yonOrange : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: RadarCanvas(
                  active: _status == SignalingStatus.connected,
                ),
              ),
              Positioned.fill(
                child: _RadarPeers(
                  self: _selfDevice,
                  peers: _peers,
                  connectedPeerIds: _connectedPeerIds,
                  onTapPeer: _pickAndSend,
                  onLongPressPeer: _sendTextMessage,
                  onDropFiles: (peer, files) => _sendFiles(peer, files),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Text(
                    _peers.isEmpty
                        ? 'ກຳລັງຊອກຫາອຸປະກອນ...'
                        : 'ແຕະໃສ່ອຸປະກອນເພື່ອເລືອກໄຟລ໌ · ລາກໄຟລ໌ມາວາງ',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.black45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransferPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? YonTheme.slateDarkCard.withValues(alpha: 0.8)
            : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: YonTheme.yonOrange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                color: YonTheme.yonOrange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'ສະຖານະການໂຍນໄຟລ໌',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_transfers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'ຍັງບໍ່ມີການໂຍນໄຟລ໌',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            )
          else
            TransferSheet(
              transfers: _transfers,
              onCancel: _cancelTransfer,
              showHeader: false,
            ),
        ],
      ),
    );
  }

  void _showPinSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? YonTheme.slateDarkBg
              : YonTheme.lightBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SafeArea(
          top: false,
          child: PinRoomCard(
            ownPin: _ownPin,
            joinedPin: _joinedPin,
            onJoinPin: (pin) {
              _joinPin(pin);
              Navigator.pop(context);
            },
            onLeavePin: _leavePin,
            onScan: () {
              Navigator.pop(context);
              _openScanner();
            },
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ Radar peers ------------------------------ */

class _RadarPeers extends StatelessWidget {
  const _RadarPeers({
    required this.self,
    required this.peers,
    required this.connectedPeerIds,
    required this.onTapPeer,
    required this.onLongPressPeer,
    required this.onDropFiles,
  });

  final PeerDevice self;
  final List<PeerDevice> peers;
  final Set<String> connectedPeerIds;
  final void Function(PeerDevice) onTapPeer;
  final void Function(PeerDevice) onLongPressPeer;
  final void Function(PeerDevice, List<PickedFile>) onDropFiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );
        final radius =
            (math.min(constraints.maxWidth, constraints.maxHeight) / 2) - 70;

        final widgets = <Widget>[];
        widgets.add(
          Positioned(
            left: center.dx - 52,
            top: center.dy - 52,
            child: PeerAvatar(peer: self, isSelf: true, diameter: 88),
          ),
        );

        final count = peers.length;
        for (var i = 0; i < count; i++) {
          final angle = -math.pi / 2 + (i * 2 * math.pi / count);
          final dx = center.dx + radius * math.cos(angle) - 44;
          final dy = center.dy + radius * math.sin(angle) - 44;
          final peer = peers[i];
          widgets.add(
            Positioned(
              left: dx,
              top: dy,
              child: GestureDetector(
                onLongPress: () => onLongPressPeer(peer),
                child: PeerAvatar(
                  peer: peer,
                  diameter: 76,
                  isConnected: connectedPeerIds.contains(peer.id),
                  onTap: () => onTapPeer(peer),
                  onFilesDropped: (files) => onDropFiles(peer, files),
                ),
              ),
            ),
          );
        }
        return Stack(children: widgets);
      },
    );
  }
}

/* ----------------------------- Small widgets ----------------------------- */

class _BadgeIconButton extends StatelessWidget {
  const _BadgeIconButton({
    required this.icon,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(onPressed: onTap, icon: Icon(icon)),
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: YonTheme.yonOrange,
              shape: BoxShape.circle,
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ------------------------------ QR Scanner ------------------------------- */

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();

  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      final digits = RegExp(r'\d{6}').firstMatch(value)?.group(0);
      if (digits != null) {
        _handled = true;
        Navigator.of(context).pop(digits);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ສະແກນ QR Code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              _error ??= error.errorDetails?.message ?? error.errorCode.name;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.no_photography_rounded,
                        size: 48,
                        color: YonTheme.roseRed,
                      ),
                      const SizedBox(height: 12),
                      const Text('ເປີດກ້ອງບໍ່ໄດ້'),
                      const SizedBox(height: 6),
                      Text(
                        _error ?? 'ກະລຸນາອະນຸຍາດການໃຊ້ກ້ອງ ແລະໃຊ້ HTTPS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _controller.start(),
                        child: const Text('ລອງໃໝ່'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Text(
                'ຈັດ QR Code ໃຫ້ຢູ່ໃນກອບ',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
