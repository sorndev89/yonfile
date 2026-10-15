import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/file_transfer_controller.dart';
import '../../core/constants/app_config.dart';
import '../../core/theme/yon_theme.dart';
import '../../models/file_transfer_state.dart';
import '../../models/peer_device.dart';
import '../../models/picked_file.dart';
import '../../services/local_signaling_host.dart';
import '../../services/signaling_service.dart';
import '../../services/webrtc_service.dart';
import '../widgets/home_header.dart';
import '../widgets/pin_room_card.dart';
import '../widgets/peer_os_badge.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/transfer_history_card.dart';
import '../widgets/transfer_status_panel.dart';
import 'connection_screen.dart';
import 'qr_scanner_screen.dart';
import 'radar_screen.dart';

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
  late final FileTransferController _fileTransfers;
  final LocalSignalingHost _localHost = LocalSignalingHost();
  late final String _onlineSignalingUrl;

  final List<StreamSubscription<dynamic>> _subs = [];

  SignalingStatus _status = SignalingStatus.disconnected;
  String? _peerId;

  final Map<String, PeerDevice> _lanPeers = {};
  final Map<String, PeerDevice> _pinPeers = {};

  String _myName = 'ອຸປະກອນຂອງຂ້ອຍ';
  PeerDeviceType _myDeviceType = PeerDeviceType.desktop;
  bool _deviceTypeResolved = false;
  bool _localHostRunning = false;
  bool _usingLocalSignaling = false;

  String _ownPin = _randomPin();
  String? _joinedPin;

  final Set<String> _connectedPeerIds = {};
  final Set<String> _connectingPeerIds = {};
  final Set<String> _knownCompletedTransfers = {};
  String? _activePeerId;
  bool _transferSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _onlineSignalingUrl = AppConfig.signalingUrl;
    _signaling = SignalingService()..joinPin(_ownPin);
    _webrtc = WebRtcService(_signaling);
    _fileTransfers = FileTransferController(
      webrtc: _webrtc,
      peerName: _peerName,
      onIncomingText: _showIncomingText,
    )..addListener(_onTransferStateChanged);
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
    _signaling.register(_myName, _myDeviceType, _myOperatingSystem);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_deviceTypeResolved) return;
    _deviceTypeResolved = true;
    _myDeviceType = _detectDeviceType();
    _signaling.register(_myName, _myDeviceType, _myOperatingSystem);
  }

  PeerDeviceType _detectDeviceType() {
    final size = MediaQuery.sizeOf(context);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return size.shortestSide < 600
            ? PeerDeviceType.mobile
            : PeerDeviceType.tablet;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return PeerDeviceType.desktop;
      case TargetPlatform.fuchsia:
        if (size.width < 600) return PeerDeviceType.mobile;
        if (size.width < 1100) return PeerDeviceType.tablet;
        return PeerDeviceType.desktop;
    }
  }

  PeerOperatingSystem get _myOperatingSystem =>
      PeerDevice.fromTargetPlatform(defaultTargetPlatform);

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
        final pinRoomPeers = event.peers
            .where((peer) => peer.id != _peerId)
            .toList(growable: false);
        if (event.scope == PeerScope.pin &&
            event.pin == _ownPin &&
            pinRoomPeers.length == 1) {
          unawaited(_connectToPinPeer(pinRoomPeers.single));
        }
      }),
    );

    _subs.add(
      _webrtc.channelStates.listen((event) {
        if (!mounted) return;
        setState(() {
          if (event.isOpen) {
            _connectedPeerIds.add(event.peerId);
            _activePeerId ??= event.peerId;
          } else {
            _connectedPeerIds.remove(event.peerId);
            if (_activePeerId == event.peerId) _activePeerId = null;
            _fileTransfers.onPeerDisconnected(event.peerId);
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
    _fileTransfers.dispose();
    _webrtc.dispose();
    _signaling.dispose();
    _localHost.stop();
    super.dispose();
  }

  void _onTransferStateChanged() {
    final completedIds = _fileTransfers.transfers
        .where((transfer) => transfer.status == TransferStatus.completed)
        .map((transfer) => transfer.id)
        .toSet();
    final completedNewTransfer = completedIds.any(
      (id) => !_knownCompletedTransfers.contains(id),
    );
    _knownCompletedTransfers.addAll(completedIds);
    final hasActiveTransfers = _fileTransfers.transfers.any(
      (transfer) => transfer.isActive,
    );

    if (mounted &&
        _transferSheetOpen &&
        completedNewTransfer &&
        !hasActiveTransfers) {
      _transferSheetOpen = false;
      Navigator.of(context).pop();
    }
    if (mounted) setState(() {});
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

  static String _randomPin() {
    final random = math.Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  PeerDevice get _selfDevice => PeerDevice(
    id: _peerId ?? 'self',
    name: _myName,
    deviceType: _myDeviceType,
    operatingSystem: _myOperatingSystem,
    scope: PeerScope.lan,
  );

  PeerDevice? get _activePeer {
    final id = _activePeerId;
    if (id == null) return null;
    for (final peer in _peers) {
      if (peer.id == id) return peer;
    }
    // Keep the connection screen available if signaling removes the peer from
    // its current room while the already-open data channel is still alive.
    if (!_connectedPeerIds.contains(id)) return null;
    return PeerDevice(
      id: id,
      name: 'YonFile',
      deviceType: PeerDeviceType.desktop,
      operatingSystem: PeerOperatingSystem.unknown,
      scope: PeerScope.lan,
    );
  }

  bool get _hasActiveConnection {
    final peer = _activePeer;
    return peer != null && _connectedPeerIds.contains(peer.id);
  }

  /* --------------------------- File sending ---------------------------- */

  Future<void> _pickAndSend(PeerDevice peer) async {
    final pinWasAlreadyJoined =
        peer.scope == PeerScope.pin || _pinPeers.containsKey(peer.id);
    if (!await _ensurePinAccess(peer)) return;
    if (!pinWasAlreadyJoined) {
      // First PIN entry establishes the connection. Let the user review the
      // connected-device screen before choosing any files to send.
      await _connectToPinPeer(peer);
      return;
    }
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
      if (mounted) setState(() => _activePeerId = peer.id);
    } catch (error) {
      await _webrtc.closeSession(peer.id);
      _snack('ເຊື່ອມຕໍ່ກັບ ${peer.name} ບໍ່ສຳເລັດ ກະລຸນາລອງໃໝ່');
      debugPrint('connect error: $error');
      return;
    }
    await _fileTransfers.sendFiles(peer, files);
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

  /* ------------------------------- Actions ----------------------------- */

  void _joinPin(String pin) {
    _signaling.joinPin(pin);
    setState(() {
      _joinedPin = pin;
      _ownPin = pin;
      _pinPeers.clear();
    });
    _snack('ກຳລັງເຂົ້າຫ້ອງ PIN');
  }

  Future<void> _connectToPinPeer(PeerDevice peer) async {
    if (!_connectingPeerIds.add(peer.id)) return;
    try {
      if (!_webrtc.isOpen(peer.id)) {
        await _webrtc.connect(peer.id);
        await _webrtc.waitUntilOpen(peer.id);
      }
      if (!mounted || !_webrtc.isOpen(peer.id)) return;
      setState(() => _activePeerId = peer.id);
    } catch (error) {
      debugPrint('PIN peer connection failed (${peer.id}): $error');
      if (mounted) _snack('ເຊື່ອມຕໍ່ ${peer.name} ບໍ່ສຳເລັດ ກະລຸນາລອງໃໝ່');
    } finally {
      _connectingPeerIds.remove(peer.id);
    }
  }

  void _leavePin() {
    _changePin(showMessage: false);
  }

  void _changePin({bool showMessage = true}) {
    _signaling.leavePin();
    final nextPin = _randomPin();
    _signaling.joinPin(nextPin);
    setState(() {
      _joinedPin = null;
      _pinPeers.clear();
      _ownPin = nextPin;
    });
    if (showMessage) _snack('ປ່ຽນ PIN ໃໝ່ແລ້ວ');
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
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));
    if (pin != null && pin.length == 6) _joinPin(pin);
  }

  void _openTransferSheet() {
    if (!mounted) return;
    _knownCompletedTransfers.addAll(
      _fileTransfers.transfers
          .where((transfer) => transfer.status == TransferStatus.completed)
          .map((transfer) => transfer.id),
    );
    _transferSheetOpen = true;
    TransferSheet.show(
      context,
      transfers: _fileTransfers.transfers,
      revision: _fileTransfers.revision,
      onCancel: _fileTransfers.cancelTransfer,
      onClearCompleted: () {
        _fileTransfers.clearCompleted();
        Navigator.pop(context);
      },
    ).whenComplete(() => _transferSheetOpen = false);
  }

  Future<void> _disconnectActivePeer() async {
    final peerId = _activePeerId;
    if (peerId == null) return;
    _fileTransfers.onPeerDisconnected(peerId);
    await _webrtc.closeSession(peerId);
    if (!mounted) return;
    setState(() {
      _connectedPeerIds.remove(peerId);
      _activePeerId = null;
    });
  }

  /* ------------------------------- Helpers ----------------------------- */

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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                peer.typeLabel,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 8),
                              PeerOsBadge(peer: peer, compact: true),
                            ],
                          ),
                        ],
                      ),
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

  Widget _buildTopBar() => HomeHeader(
    signalingConnected: _status == SignalingStatus.connected,
    usingLocalSignaling: _usingLocalSignaling,
    activeTransferCount: _fileTransfers.transfers
        .where((transfer) => transfer.isActive)
        .length,
    themeMode: widget.themeMode,
    onOfflineSettings: _showOfflineOptions,
    onTransferHistory: _openTransferSheet,
    onToggleTheme: widget.onToggleTheme,
  );

  Widget _buildMobile() {
    return Column(
      children: [
        _buildTopBar(),
        _buildDeviceNameRow(),
        Expanded(child: _buildMainStage()),
        if (!_hasActiveConnection)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showPinSheet,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('PIN'),
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
    final isConnected = _hasActiveConnection;
    return Column(
      children: [
        _buildTopBar(),
        _buildDeviceNameRow(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildMainStage()),
              SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 16, 16),
                  child: ListView(
                    children: [
                      if (isConnected) ...[
                        TransferHistoryCard(
                          transfers: _fileTransfers.transfers,
                        ),
                      ] else ...[
                        PinRoomCard(
                          ownPin: _ownPin,
                          joinedPin: _joinedPin,
                          onJoinPin: _joinPin,
                          onLeavePin: _leavePin,
                          onChangePin: _changePin,
                          onScan: _openScanner,
                        ),
                        const SizedBox(height: 16),
                        _buildTransferPanel(),
                      ],
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

  Widget _buildMainStage() {
    final peer = _activePeer;
    if (peer != null && _connectedPeerIds.contains(peer.id)) {
      return _buildConnectionStage(peer);
    }
    return RadarScreen(
      self: _selfDevice,
      peers: _peers,
      connectedPeerIds: _connectedPeerIds,
      signalingConnected: _status == SignalingStatus.connected,
      onTapPeer: _pickAndSend,
      onLongPressPeer: _sendTextMessage,
      onDroppedFiles: _sendDroppedFiles,
      onDropRejected: _snack,
    );
  }

  Widget _buildConnectionStage(PeerDevice peer) {
    final transfers = _fileTransfers.transfersForPeer(peer.id, peer.name);
    return ConnectionScreen(
      self: _selfDevice,
      peer: peer,
      pendingOffers: _fileTransfers.pendingIncomingOffers.values
          .where((offer) => offer.peerId == peer.id)
          .toList(),
      transfers: transfers,
      hasActiveTransfer: _fileTransfers.hasActiveTransferForPeer(peer.id),
      onSendFile: () => _pickAndSend(peer),
      onDisconnect: _disconnectActivePeer,
      onAccept: _fileTransfers.acceptIncomingOffer,
      onReject: _fileTransfers.rejectIncomingOffer,
      onCancelTransfer: _fileTransfers.cancelTransfer,
      showHistory: MediaQuery.sizeOf(context).width < 600,
    );
  }

  Widget _buildDeviceNameRow() =>
      DeviceNameHeader(name: _myName, icon: _selfDevice.icon, onTap: _editName);

  Widget _buildTransferPanel() => TransferStatusPanel(
    transfers: _fileTransfers.transfers,
    onCancel: _fileTransfers.cancelTransfer,
  );

  void _showPinSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
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
                Navigator.pop(sheetContext);
              },
              onLeavePin: () {
                _leavePin();
                setSheetState(() {});
              },
              onChangePin: () {
                _changePin();
                setSheetState(() {});
              },
              onScan: () {
                Navigator.pop(sheetContext);
                _openScanner();
              },
            ),
          ),
        ),
      ),
    );
  }
}
