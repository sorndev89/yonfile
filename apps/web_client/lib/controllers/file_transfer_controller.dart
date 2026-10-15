import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_config.dart';
import '../models/file_transfer_state.dart';
import '../models/incoming_file_offer.dart';
import '../models/peer_device.dart';
import '../models/picked_file.dart';
import '../services/file_chunker_service.dart';
import '../services/webrtc_service.dart';

/// Owns transfer protocol state and coordinates file messages over WebRTC.
class FileTransferController extends ChangeNotifier {
  FileTransferController({
    required WebRtcService webrtc,
    required String Function(String peerId) peerName,
    this.onIncomingText,
  }) : _webrtc = webrtc,
       _peerName = peerName {
    _messageSubscription = _webrtc.messages.listen(handlePeerMessage);
  }

  final WebRtcService _webrtc;
  final String Function(String peerId) _peerName;
  final void Function(String peerId, String text)? onIncomingText;
  final FileChunkerService _chunker = FileChunkerService();
  final math.Random _random = math.Random.secure();

  final List<FileTransferState> _transfers = [];
  final Map<String, Uint8List> _outgoingBytes = {};
  final Map<String, Completer<bool>> _pendingAccepts = {};
  final Map<String, IncomingFile> _incoming = {};
  final Map<String, String> _activeIncomingId = {};
  final Map<String, String> _transferPeers = {};
  final Map<String, IncomingFileOffer> _pendingIncomingOffers = {};
  final Set<String> _cancelled = {};
  final ValueNotifier<int> revision = ValueNotifier(0);
  late final StreamSubscription<PeerMessage> _messageSubscription;
  bool _disposed = false;

  List<FileTransferState> get transfers => UnmodifiableListView(_transfers);
  Map<String, IncomingFileOffer> get pendingIncomingOffers =>
      Map.unmodifiable(_pendingIncomingOffers);
  int get incomingReservedBytes =>
      _incoming.values.fold(0, (total, file) => total + file.fileSize);

  List<FileTransferState> transfersForPeer(String peerId, String peerName) =>
      _transfers
          .where(
            (transfer) =>
                transfer.peerName == peerName ||
                _transferPeers[transfer.id] == peerId ||
                _pendingIncomingOffers[transfer.id]?.peerId == peerId,
          )
          .toList();

  bool hasActiveTransferForPeer(String peerId) => _transfers.any(
    (transfer) =>
        transfer.isActive &&
        (_transferPeers[transfer.id] == peerId ||
            _pendingIncomingOffers[transfer.id]?.peerId == peerId),
  );

  Future<void> sendFiles(PeerDevice peer, List<PickedFile> files) async {
    for (final file in files) {
      await _sendSingleFile(peer, file);
    }
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
      if (_webrtc.isOpen(peer.id)) {
        await _webrtc.sendText(
          peer.id,
          jsonEncode({'type': 'cancel-file', 'id': id}),
        );
      }
    } catch (error) {
      _updateTransfer(
        id,
        (t) => t.copyWith(status: TransferStatus.failed, error: '$error'),
      );
    } finally {
      _outgoingBytes.remove(id);
      final waitingForCompletion = _transfers.any(
        (transfer) =>
            transfer.id == id && transfer.status == TransferStatus.verifying,
      );
      if (!waitingForCompletion) _transferPeers.remove(id);
      _cancelled.remove(id);
      _pendingAccepts.remove(id);
    }
  }

  void handlePeerMessage(PeerMessage message) {
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
      case 'accept-file':
        final id = data['id'];
        final pending = id is String ? _pendingAccepts[id] : null;
        if (pending != null && !pending.isCompleted) pending.complete(true);
      case 'reject-file':
        final id = data['id'];
        final pending = id is String ? _pendingAccepts[id] : null;
        if (pending != null && !pending.isCompleted) pending.complete(false);
      case 'eof':
        _onEof(message.peerId, data);
      case 'transfer-complete':
        _onTransferComplete(data);
      case 'cancel-file':
        _onRemoteCancel(data);
      case 'text':
        if (data['text'] is String) {
          onIncomingText?.call(message.peerId, data['text'] as String);
        }
    }
  }

  void onPeerDisconnected(String peerId) {
    for (final offer in _pendingIncomingOffers.values.where(
      (offer) => offer.peerId == peerId,
    )) {
      if (!offer.response.isCompleted) offer.response.complete(false);
    }
    for (final entry in _transferPeers.entries.toList()) {
      if (entry.value == peerId) {
        final pending = _pendingAccepts[entry.key];
        if (pending != null && !pending.isCompleted) pending.complete(false);
      }
    }
  }

  Future<void> _onOfferFile(String peerId, Map<String, dynamic> data) async {
    final id = data['id'] is String ? data['id'] as String : '';
    final rawName = data['name'] is String ? data['name'] as String : 'file';
    final name = rawName.replaceAll(RegExp(r'[\\/\u0000-\u001f]'), '_').trim();
    final size = data['size'] is num ? (data['size'] as num).toInt() : -1;
    final peerName = _peerName(peerId);
    String? rejectionReason;
    if (id.isEmpty || name.isEmpty || size < 0) {
      rejectionReason = 'ຂໍ້ມູນໄຟລ໌ບໍ່ຄົບຖ້ວນ';
    } else if (size > AppConfig.maxFileSizeBytes ||
        incomingReservedBytes + size > AppConfig.maxFileSizeBytes) {
      rejectionReason = 'ໄຟລ໌ໃຫຍ່ເກີນຂີດຈຳກັດ';
    } else if (_activeIncomingId.containsKey(peerId) ||
        _pendingIncomingOffers.values.any((offer) => offer.peerId == peerId)) {
      rejectionReason = 'ມີການຮັບໄຟລ໌ອື່ນຄ້າງຢູ່';
    }
    if (rejectionReason != null) {
      if (id.isNotEmpty && name.isNotEmpty && size >= 0) {
        _upsertTransfer(
          FileTransferState(
            id: id,
            fileName: name,
            fileSize: size,
            direction: TransferDirection.receive,
            peerName: peerName,
            status: TransferStatus.failed,
            error: rejectionReason,
            startedAt: DateTime.now(),
          ),
        );
      }
      if (_webrtc.isOpen(peerId)) {
        await _webrtc.sendText(
          peerId,
          jsonEncode({'type': 'reject-file', 'id': id}),
        );
      }
      return;
    }
    if (_pendingIncomingOffers.containsKey(id)) return;

    final offer = IncomingFileOffer(
      id: id,
      peerId: peerId,
      peerName: peerName,
      fileName: name,
      fileSize: size,
    );
    _pendingIncomingOffers[id] = offer;
    _upsertTransfer(
      FileTransferState(
        id: id,
        fileName: name,
        fileSize: size,
        direction: TransferDirection.receive,
        peerName: peerName,
        status: TransferStatus.offering,
        startedAt: DateTime.now(),
      ),
    );
    final accepted = await offer.response.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => false,
    );
    _pendingIncomingOffers.remove(id);
    if (!accepted) {
      _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
      if (_webrtc.isOpen(peerId)) {
        await _webrtc.sendText(
          peerId,
          jsonEncode({'type': 'reject-file', 'id': id}),
        );
      }
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
    if (_webrtc.isOpen(peerId)) {
      await _webrtc.sendText(
        peerId,
        jsonEncode({'type': 'accept-file', 'id': id}),
      );
    } else {
      _incoming.remove(id);
      _activeIncomingId.remove(peerId);
      _transferPeers.remove(id);
      _updateTransfer(
        id,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          error: 'ການເຊື່ອມຕໍ່ຖືກຕັດກ່ອນເລີ່ມຮັບໄຟລ໌',
        ),
      );
    }
  }

  void _onBinary(String peerId, Uint8List bytes) {
    final id = _activeIncomingId[peerId];
    final incoming = id == null ? null : _incoming[id];
    if (id == null || incoming == null) return;
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

  Future<void> _onEof(String peerId, Map<String, dynamic> data) async {
    final id = data['id'] is String ? data['id'] as String : '';
    final incoming = _incoming[id];
    if (id.isEmpty || incoming == null) return;
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.verifying));
    final expected = data['sha256'] is String ? data['sha256'] as String : null;
    final bytes = incoming.takeBytes();
    final actual = _chunker.sha256Of(bytes);
    final verified =
        incoming.received == incoming.fileSize &&
        expected != null &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(expected) &&
        expected == actual;
    Uri? savedFile;
    var saveCompleted = false;
    try {
      if (verified) {
        savedFile = await FilePicker.saveFile(
          fileName: incoming.fileName,
          bytes: bytes,
        );
        // Web downloads intentionally return null because browsers hide paths.
        saveCompleted = true;
      }
    } catch (error) {
      debugPrint('save error: $error');
    }
    final completed =
        verified && saveCompleted && (kIsWeb || savedFile != null);
    if (_webrtc.isOpen(peerId)) {
      await _webrtc.sendText(
        peerId,
        jsonEncode({
          'type': 'transfer-complete',
          'id': id,
          'verified': completed,
        }),
      );
    }
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
    _transferPeers.remove(id);
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
    final pendingOffer = _pendingIncomingOffers.remove(id);
    if (pendingOffer != null && !pendingOffer.response.isCompleted) {
      pendingOffer.response.complete(false);
    }
    final pending = _pendingAccepts[id];
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final peerId = _transferPeers.remove(id);
    _incoming.remove(id);
    if (peerId != null && _activeIncomingId[peerId] == id) {
      _activeIncomingId.remove(peerId);
    }
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
  }

  void acceptIncomingOffer(String id) {
    final offer = _pendingIncomingOffers[id];
    if (offer != null && !offer.response.isCompleted) {
      offer.response.complete(true);
    }
  }

  void rejectIncomingOffer(String id) {
    final offer = _pendingIncomingOffers[id];
    if (offer != null && !offer.response.isCompleted) {
      offer.response.complete(false);
    }
  }

  void cancelTransfer(String id) {
    final index = _transfers.indexWhere((transfer) => transfer.id == id);
    if (index < 0 || !_transfers[index].isActive) return;
    _cancelled.add(id);
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
    final offer = _pendingIncomingOffers.remove(id);
    if (offer != null && !offer.response.isCompleted) {
      offer.response.complete(false);
    }
    final pending = _pendingAccepts[id];
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final peerId = _transferPeers[id];
    if (peerId != null) {
      if (_webrtc.isOpen(peerId)) {
        _webrtc.sendText(peerId, jsonEncode({'type': 'cancel-file', 'id': id}));
      }
      final isIncoming = _incoming.remove(id) != null;
      if (isIncoming) _cancelled.remove(id);
      if (_activeIncomingId[peerId] == id) _activeIncomingId.remove(peerId);
    }
  }

  void clearCompleted() {
    _transfers.removeWhere((transfer) => !transfer.isActive);
    _notifyChanged();
  }

  void _upsertTransfer(FileTransferState transfer) {
    final index = _transfers.indexWhere((item) => item.id == transfer.id);
    if (index >= 0) {
      _transfers[index] = transfer;
    } else {
      _transfers.insert(0, transfer);
    }
    _notifyChanged();
  }

  void _updateTransfer(
    String id,
    FileTransferState Function(FileTransferState) update,
  ) {
    final index = _transfers.indexWhere((transfer) => transfer.id == id);
    if (index < 0) return;
    _transfers[index] = update(_transfers[index]);
    _notifyChanged();
  }

  void _notifyChanged() {
    if (_disposed) return;
    revision.value++;
    notifyListeners();
  }

  String _generateId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(9999)}';

  @override
  void dispose() {
    _disposed = true;
    _messageSubscription.cancel();
    revision.dispose();
    super.dispose();
  }
}
