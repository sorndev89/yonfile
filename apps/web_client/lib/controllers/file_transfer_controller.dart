import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_config.dart';
import '../models/file_transfer_state.dart';
import '../models/incoming_file_offer.dart';
import '../models/peer_device.dart';
import '../models/picked_file.dart';
import '../services/file_chunker_service.dart';
import '../services/incoming_file_sink.dart';
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
    _historyReady = _restoreHistory();
  }

  static const String _historyKey = 'file_transfer_history_v1';

  final WebRtcService _webrtc;
  final String Function(String peerId) _peerName;
  final void Function(String peerId, String text)? onIncomingText;
  final FileChunkerService _chunker = FileChunkerService();
  final math.Random _random = math.Random.secure();

  final List<FileTransferState> _transfers = [];
  final Map<String, Uint8List> _outgoingBytes = {};
  final Map<String, Completer<bool>> _pendingAccepts = {};
  final Map<String, Completer<bool>> _pendingCompletions = {};
  final Set<String> _sending = {};
  final Map<String, IncomingFile> _incoming = {};
  final Map<String, IncomingFileSink> _preparedSinks = {};
  final Map<String, Future<void>> _incomingWrites = {};
  final Map<String, int> _incomingUnackedBytes = {};
  final Map<String, _ChunkAckState> _chunkAckStates = {};
  final Map<String, String> _activeIncomingId = {};
  final Map<String, String> _transferPeers = {};
  final Map<String, IncomingFileOffer> _pendingIncomingOffers = {};
  final Set<String> _cancelled = {};
  final Map<String, int> _lastIncomingUiMs = {};
  static const int _ackWindowBytes = 2 * 1024 * 1024;
  final ValueNotifier<int> revision = ValueNotifier(0);
  late final StreamSubscription<PeerMessage> _messageSubscription;
  late final Future<void> _historyReady;
  Future<void> _historyWrite = Future<void>.value();
  bool _disposed = false;

  List<FileTransferState> get transfers => UnmodifiableListView(_transfers);
  Map<String, IncomingFileOffer> get pendingIncomingOffers =>
      Map.unmodifiable(_pendingIncomingOffers);
  int get incomingReservedBytes =>
      _incoming.values.fold(0, (total, file) => total + file.fileSize);
  int get _pendingOfferBytes => _pendingIncomingOffers.values.fold(
    0,
    (total, offer) => total + offer.fileSize,
  );

  List<FileTransferState> transfersForPeer(String peerId, String peerName) =>
      _transfers
          .where(
            (transfer) =>
                transfer.peerId == peerId ||
                (transfer.peerId == null && transfer.peerName == peerName) ||
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
    if (file.bytes != null) _outgoingBytes[id] = file.bytes!;
    _sending.add(id);
    _transferPeers[id] = peer.id;
    _upsertTransfer(
      FileTransferState(
        id: id,
        fileName: file.name,
        fileSize: file.size,
        direction: TransferDirection.send,
        peerName: peer.name,
        peerId: peer.id,
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

      _updateTransfer(
        id,
        (t) => t.copyWith(status: TransferStatus.transferring),
      );
      final stopwatch = Stopwatch()..start();
      var lastUiMs = 0;
      void onProgress(int sent) {
        final nowMs = stopwatch.elapsedMilliseconds;
        if (sent >= file.size || nowMs - lastUiMs >= 100) {
          lastUiMs = nowMs;
          final seconds = nowMs / 1000.0;
          _updateTransfer(
            id,
            (t) => t.copyWith(
              transferred: sent,
              bytesPerSecond: seconds > 0.2 ? sent / seconds : 0,
            ),
          );
        }
      }

      final sha = file.readStream != null
          ? await _chunker.sendStream(
              stream: file.readStream!,
              expectedSize: file.size,
              sendChunk: (chunk) => _sendBinaryChunk(id, peer.id, chunk),
              bufferedAmount: () => _webrtc.bufferedAmount(peer.id),
              onProgress: onProgress,
              isCancelled: () => _cancelled.contains(id),
              isChannelOpen: () => _webrtc.isOpen(peer.id),
            )
          : await _sendBytesWithProgress(id, peer, file, onProgress);
      await _flushSendWindow(id, peer.id);
      if (_cancelled.contains(id)) throw const TransferCancelledException();
      _updateTransfer(id, (t) => t.copyWith(sha256: sha));
      final completion = Completer<bool>();
      _pendingCompletions[id] = completion;
      _updateTransfer(
        id,
        (t) => t.copyWith(
          status: TransferStatus.verifying,
          transferred: file.size,
        ),
      );
      await _webrtc.sendText(
        peer.id,
        jsonEncode({'type': 'eof', 'id': id, 'sha256': sha}),
      );
      final completed = await completion.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => false,
      );
      if (!completed) {
        _updateTransfer(
          id,
          (t) => t.copyWith(
            status: TransferStatus.failed,
            error: 'ບໍ່ໄດ້ຮັບຄຳຢືນຢັນຈາກອຸປະກອນປາຍທາງ',
          ),
        );
      }
    } on TransferCancelledException {
      _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
      if (_webrtc.isOpen(peer.id)) {
        await _webrtc.sendText(
          peer.id,
          jsonEncode({'type': 'cancel-file', 'id': id}),
        );
      }
    } catch (error) {
      if (_webrtc.isOpen(peer.id)) {
        try {
          await _webrtc.sendText(
            peer.id,
            jsonEncode({'type': 'cancel-file', 'id': id}),
          );
        } catch (_) {}
      }
      _updateTransfer(
        id,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          error: error is TransferStalledException
              ? 'ການສົ່ງຢຸດຊະງັກ ກະລຸນາລອງສົ່ງໃໝ່'
              : '$error',
        ),
      );
    } finally {
      _outgoingBytes.remove(id);
      _sending.remove(id);
      final waitingForCompletion = _transfers.any(
        (transfer) =>
            transfer.id == id && transfer.status == TransferStatus.verifying,
      );
      if (!waitingForCompletion) _transferPeers.remove(id);
      _cancelled.remove(id);
      _pendingAccepts.remove(id);
      _pendingCompletions.remove(id);
      _chunkAckStates.remove(id);
    }
  }

  Future<void> _sendBinaryChunk(
    String id,
    String peerId,
    Uint8List chunk,
  ) async {
    final state = _chunkAckStates.putIfAbsent(id, _ChunkAckState.new);
    final nextSent = state.sent + chunk.length;
    final waitForAck = nextSent - state.acknowledged >= _ackWindowBytes;
    if (waitForAck) {
      state.target = nextSent;
      state.pending ??= Completer<void>();
    }
    state.sent = nextSent;
    await _webrtc.sendBinary(peerId, chunk);
    if (waitForAck) {
      await state.pending!.future.timeout(
        const Duration(seconds: AppConfig.transferStallTimeoutSeconds),
        onTimeout: () => throw const TransferStalledException(),
      );
      if (_cancelled.contains(id)) throw const TransferCancelledException();
    }
  }

  Future<void> _flushSendWindow(String id, String peerId) async {
    final state = _chunkAckStates[id];
    if (state == null || state.sent <= state.acknowledged) return;
    state.target = state.sent;
    state.pending ??= Completer<void>();
    await _webrtc.sendText(
      peerId,
      jsonEncode({'type': 'flush-window', 'id': id}),
    );
    await state.pending!.future.timeout(
      const Duration(seconds: AppConfig.transferStallTimeoutSeconds),
      onTimeout: () => throw const TransferStalledException(),
    );
    if (_cancelled.contains(id)) throw const TransferCancelledException();
  }

  void _releaseSendWindow(String id) {
    final pending = _chunkAckStates[id]?.pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  void _onChunkAck(String peerId, Map<String, dynamic> data) {
    final id = data['id'] is String ? data['id'] as String : '';
    final received = data['received'];
    final state = _chunkAckStates[id];
    if (id.isEmpty ||
        _transferPeers[id] != peerId ||
        state == null ||
        received is! int ||
        received < state.acknowledged ||
        received < state.target ||
        received > state.sent) {
      return;
    }
    state.acknowledged = received;
    final pending = state.pending;
    state.pending = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<String> _sendBytesWithProgress(
    String id,
    PeerDevice peer,
    PickedFile file,
    void Function(int sent) onProgress,
  ) async {
    final bytes = file.bytes!;
    await _chunker.sendFile(
      bytes: bytes,
      sendChunk: (chunk) => _sendBinaryChunk(id, peer.id, chunk),
      bufferedAmount: () => _webrtc.bufferedAmount(peer.id),
      onProgress: onProgress,
      isCancelled: () => _cancelled.contains(id),
      isChannelOpen: () => _webrtc.isOpen(peer.id),
    );
    return _chunker.sha256Of(bytes);
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
        final pending = id is String && _transferPeers[id] == message.peerId
            ? _pendingAccepts[id]
            : null;
        if (pending != null && !pending.isCompleted) pending.complete(true);
      case 'reject-file':
        final id = data['id'];
        final pending = id is String && _transferPeers[id] == message.peerId
            ? _pendingAccepts[id]
            : null;
        if (pending != null && !pending.isCompleted) pending.complete(false);
      case 'eof':
        _onEof(message.peerId, data);
      case 'chunk-ack':
        _onChunkAck(message.peerId, data);
      case 'flush-window':
        _flushIncomingWindow(message.peerId, data);
      case 'transfer-complete':
        _onTransferComplete(message.peerId, data);
      case 'cancel-file':
        _onRemoteCancel(message.peerId, data);
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
    for (final entry in _preparedSinks.entries.toList()) {
      if (_pendingIncomingOffers[entry.key]?.peerId == peerId) {
        _preparedSinks.remove(entry.key);
        unawaited(entry.value.abort());
      }
    }
    for (final entry in _transferPeers.entries.toList()) {
      if (entry.value == peerId) {
        final completion = _pendingCompletions[entry.key];
        if (completion != null && !completion.isCompleted) {
          completion.complete(false);
        }
        final pending = _pendingAccepts[entry.key];
        if (pending != null && !pending.isCompleted) pending.complete(false);
        if (_sending.contains(entry.key)) {
          _cancelled.add(entry.key);
          _releaseSendWindow(entry.key);
        }
        final incoming = _incoming.remove(entry.key);
        incoming?.dispose();
        if (incoming != null) {
          unawaited(incoming.sink?.abort() ?? Future<void>.value());
        }
        _incomingUnackedBytes.remove(entry.key);
        if (_activeIncomingId[peerId] == entry.key) {
          _activeIncomingId.remove(peerId);
        }
        if (incoming != null) {
          _updateTransfer(
            entry.key,
            (transfer) => transfer.copyWith(
              status: TransferStatus.failed,
              error: 'ການເຊື່ອມຕໍ່ຖືກຕັດຂະນະຮັບໄຟລ໌',
            ),
          );
          _transferPeers.remove(entry.key);
        } else if (!_sending.contains(entry.key) &&
            _transfers.any(
              (transfer) => transfer.id == entry.key && transfer.isActive,
            )) {
          _updateTransfer(
            entry.key,
            (transfer) => transfer.copyWith(
              status: TransferStatus.failed,
              error: 'ການເຊື່ອມຕໍ່ຖືກຕັດກ່ອນຢືນຢັນການສົ່ງ',
            ),
          );
          _transferPeers.remove(entry.key);
        }
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
    if (id.isEmpty ||
        id.length > 80 ||
        name.isEmpty ||
        name.length > 255 ||
        size < 0) {
      rejectionReason = 'ຂໍ້ມູນໄຟລ໌ບໍ່ຄົບຖ້ວນ';
    } else if (size > AppConfig.maxFileSizeBytes ||
        incomingReservedBytes + _pendingOfferBytes + size >
            AppConfig.maxFileSizeBytes ||
        _pendingIncomingOffers.length >= 4) {
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
            peerId: peerId,
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
        peerId: peerId,
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

    final sink = _preparedSinks.remove(id);
    if (sink == null) {
      _updateTransfer(
        id,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          error: 'ບໍ່ສາມາດເປີດບ່ອນບັນທຶກໄຟລ໌ໄດ້',
        ),
      );
      return;
    }
    _incoming[id] = IncomingFile(
      id: id,
      fileName: name,
      fileSize: size,
      sink: sink,
      onStalled: () => _onIncomingStalled(peerId, id),
    );
    _activeIncomingId[peerId] = id;
    _transferPeers[id] = peerId;
    _upsertTransfer(
      FileTransferState(
        id: id,
        fileName: name,
        fileSize: size,
        direction: TransferDirection.receive,
        peerName: peerName,
        peerId: peerId,
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
    final previous = _incomingWrites[id] ?? Future<void>.value();
    final queued = previous.then((_) => _writeIncomingChunk(peerId, id, bytes));
    _incomingWrites[id] = queued.catchError((Object error) {
      _failIncoming(peerId, id, 'ຂຽນໄຟລ໌ລົງອຸປະກອນບໍ່ສຳເລັດ: $error');
    });
  }

  Future<void> _writeIncomingChunk(
    String peerId,
    String id,
    Uint8List bytes,
  ) async {
    final incoming = _incoming[id];
    if (incoming == null) return;
    if (bytes.isEmpty || incoming.received + bytes.length > incoming.fileSize) {
      await _failIncoming(peerId, id, 'ຂໍ້ມູນໄຟລ໌ເກີນຂະໜາດທີ່ແຈ້ງ');
      return;
    }
    await incoming.writeChunk(bytes);
    final unacked = (_incomingUnackedBytes[id] ?? 0) + bytes.length;
    _incomingUnackedBytes[id] = unacked;
    if (unacked >= _ackWindowBytes) await _ackIncoming(peerId, id, incoming);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastUi = _lastIncomingUiMs[id] ?? 0;
    if (incoming.received >= incoming.fileSize || nowMs - lastUi >= 100) {
      _lastIncomingUiMs[id] = nowMs;
      _updateTransfer(
        id,
        (t) => t.copyWith(
          transferred: incoming.received,
          bytesPerSecond: incoming.bytesPerSecond,
        ),
      );
    }
  }

  void _flushIncomingWindow(String peerId, Map<String, dynamic> data) {
    final id = data['id'] is String ? data['id'] as String : '';
    final incoming = _incoming[id];
    if (id.isEmpty || incoming == null || _transferPeers[id] != peerId) return;
    final queued = (_incomingWrites[id] ?? Future<void>.value()).then((
      _,
    ) async {
      final current = _incoming[id];
      if (current != null) await _ackIncoming(peerId, id, current);
    });
    _incomingWrites[id] = queued.catchError((Object error) {
      _failIncoming(peerId, id, 'ຂຽນໄຟລ໌ລົງອຸປະກອນບໍ່ສຳເລັດ: $error');
    });
  }

  Future<void> _ackIncoming(
    String peerId,
    String id,
    IncomingFile incoming,
  ) async {
    _incomingUnackedBytes[id] = 0;
    if (_webrtc.isOpen(peerId)) {
      await _webrtc.sendText(
        peerId,
        jsonEncode({
          'type': 'chunk-ack',
          'id': id,
          'received': incoming.received,
        }),
      );
    }
  }

  Future<void> _failIncoming(String peerId, String id, String error) async {
    final incoming = _incoming.remove(id);
    if (incoming == null) return;
    incoming.dispose();
    await incoming.sink?.abort();
    _incomingUnackedBytes.remove(id);
    _lastIncomingUiMs.remove(id);
    if (_activeIncomingId[peerId] == id) _activeIncomingId.remove(peerId);
    _transferPeers.remove(id);
    _updateTransfer(
      id,
      (t) => t.copyWith(status: TransferStatus.failed, error: error),
    );
    if (_webrtc.isOpen(peerId)) {
      await _webrtc.sendText(
        peerId,
        jsonEncode({'type': 'cancel-file', 'id': id}),
      );
    }
  }

  Future<void> _onEof(String peerId, Map<String, dynamic> data) async {
    final id = data['id'] is String ? data['id'] as String : '';
    final incoming = _incoming[id];
    if (id.isEmpty || incoming == null || _transferPeers[id] != peerId) return;
    await _incomingWrites[id];
    if (!identical(_incoming[id], incoming)) return;
    incoming.dispose();
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.verifying));
    final expected = data['sha256'] is String ? data['sha256'] as String : null;
    final verified = await incoming.verifyWith(expected);
    var saveCompleted = false;
    try {
      if (verified) {
        await incoming.sink?.finish();
        saveCompleted = true;
      } else {
        await incoming.sink?.abort();
      }
    } catch (error) {
      debugPrint('save error: $error');
      await incoming.sink?.abort();
    }
    final completed = verified && saveCompleted;
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
    _incomingWrites.remove(id);
    _incomingUnackedBytes.remove(id);
    _lastIncomingUiMs.remove(id);
    _activeIncomingId.remove(peerId);
    _transferPeers.remove(id);
  }

  void _onIncomingStalled(String peerId, String id) {
    final incoming = _incoming.remove(id);
    if (incoming == null) return;
    incoming.dispose();
    unawaited(incoming.sink?.abort() ?? Future<void>.value());
    if (_activeIncomingId[peerId] == id) _activeIncomingId.remove(peerId);
    _transferPeers.remove(id);
    _updateTransfer(
      id,
      (transfer) => transfer.copyWith(
        status: TransferStatus.failed,
        error: 'ບໍ່ໄດ້ຮັບຂໍ້ມູນເພີ່ມເກີນ 45 ວິນາທີ ກະລຸນາລອງໃໝ່',
      ),
    );
    if (_webrtc.isOpen(peerId)) {
      _webrtc.sendText(peerId, jsonEncode({'type': 'cancel-file', 'id': id}));
    }
  }

  void _onTransferComplete(String peerId, Map<String, dynamic> data) {
    final id = data['id'] is String ? data['id'] as String : '';
    final verified = data['verified'];
    final transfer = _findTransfer(id);
    if (id.isEmpty ||
        _transferPeers[id] != peerId ||
        transfer?.direction != TransferDirection.send ||
        transfer?.status != TransferStatus.verifying ||
        verified is! bool) {
      return;
    }
    final pending = _pendingCompletions[id];
    if (pending != null && !pending.isCompleted) pending.complete(verified);
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

  void _onRemoteCancel(String senderPeerId, Map<String, dynamic> data) {
    final id = data['id'] is String ? data['id'] as String : '';
    final pendingOffer = _pendingIncomingOffers[id];
    if (id.isEmpty ||
        (_transferPeers[id] != senderPeerId &&
            pendingOffer?.peerId != senderPeerId)) {
      return;
    }
    if (_sending.contains(id)) _cancelled.add(id);
    _releaseSendWindow(id);
    _pendingIncomingOffers.remove(id);
    if (pendingOffer != null && !pendingOffer.response.isCompleted) {
      pendingOffer.response.complete(false);
    }
    final pending = _pendingAccepts[id];
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final completion = _pendingCompletions[id];
    if (completion != null && !completion.isCompleted) {
      completion.complete(false);
    }
    final peerId = _transferPeers.remove(id);
    final prepared = _preparedSinks.remove(id);
    if (prepared != null) unawaited(prepared.abort());
    final incoming = _incoming.remove(id);
    incoming?.dispose();
    if (incoming != null) {
      unawaited(incoming.sink?.abort() ?? Future<void>.value());
    }
    if (peerId != null && _activeIncomingId[peerId] == id) {
      _activeIncomingId.remove(peerId);
    }
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
  }

  Future<void> acceptIncomingOffer(String id) async {
    final offer = _pendingIncomingOffers[id];
    if (offer != null && !offer.response.isCompleted) {
      try {
        final sink = await createIncomingFileSink(offer.fileName);
        if (!offer.response.isCompleted &&
            _pendingIncomingOffers[id]?.peerId == offer.peerId) {
          _preparedSinks[id] = sink;
          offer.response.complete(true);
        } else {
          await sink.abort();
        }
      } catch (error) {
        debugPrint('Unable to prepare incoming file: $error');
        if (!offer.response.isCompleted) offer.response.complete(false);
      }
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
    _releaseSendWindow(id);
    _updateTransfer(id, (t) => t.copyWith(status: TransferStatus.cancelled));
    final offer = _pendingIncomingOffers.remove(id);
    final prepared = _preparedSinks.remove(id);
    if (prepared != null) unawaited(prepared.abort());
    if (offer != null && !offer.response.isCompleted) {
      offer.response.complete(false);
    }
    final pending = _pendingAccepts[id];
    if (pending != null && !pending.isCompleted) pending.complete(false);
    final completion = _pendingCompletions[id];
    if (completion != null && !completion.isCompleted) {
      completion.complete(false);
    }
    final peerId = _transferPeers[id];
    if (peerId != null) {
      if (_webrtc.isOpen(peerId)) {
        _webrtc.sendText(peerId, jsonEncode({'type': 'cancel-file', 'id': id}));
      }
      final incoming = _incoming.remove(id);
      final isIncoming = incoming != null;
      if (isIncoming) {
        // The receiver no longer owns the in-memory assembly or peer lock.
        incoming.dispose();
        unawaited(incoming.sink?.abort() ?? Future<void>.value());
        _cancelled.remove(id);
        _transferPeers.remove(id);
      }
      if (_activeIncomingId[peerId] == id) _activeIncomingId.remove(peerId);
    }
  }

  void clearCompleted() {
    _transfers.removeWhere((transfer) => !transfer.isActive);
    _notifyChanged();
    unawaited(_persistHistory());
  }

  void _upsertTransfer(FileTransferState transfer) {
    final index = _transfers.indexWhere((item) => item.id == transfer.id);
    if (index >= 0) {
      _transfers[index] = transfer;
    } else {
      _transfers.insert(0, transfer);
    }
    _notifyChanged();
    if (!transfer.isActive) unawaited(_persistHistory());
  }

  void _updateTransfer(
    String id,
    FileTransferState Function(FileTransferState) update,
  ) {
    final index = _transfers.indexWhere((transfer) => transfer.id == id);
    if (index < 0) return;
    final current = _transfers[index];
    if (current.status == TransferStatus.completed ||
        current.status == TransferStatus.failed ||
        current.status == TransferStatus.cancelled) {
      return;
    }
    _transfers[index] = update(current);
    _notifyChanged();
    if (!_transfers[index].isActive) unawaited(_persistHistory());
  }

  Future<void> _restoreHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawHistory = prefs.getString(_historyKey);
      if (rawHistory == null) return;
      final decoded = jsonDecode(rawHistory);
      if (decoded is! List) return;
      final restored = decoded
          .map(FileTransferState.fromJson)
          .whereType<FileTransferState>()
          .where((transfer) => !transfer.isActive)
          .take(100);
      for (final transfer in restored) {
        if (_transfers.every((current) => current.id != transfer.id)) {
          _transfers.add(transfer);
        }
      }
      _notifyChanged();
    } catch (error) {
      debugPrint('Unable to restore transfer history: $error');
    }
  }

  Future<void> _persistHistory() {
    _historyWrite = _historyWrite.then((_) async {
      await _historyReady;
      try {
        final history = _transfers
            .where((transfer) => !transfer.isActive)
            .take(100)
            .map((transfer) => transfer.toJson())
            .toList();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_historyKey, jsonEncode(history));
      } catch (error) {
        debugPrint('Unable to persist transfer history: $error');
      }
    });
    return _historyWrite;
  }

  void _notifyChanged() {
    if (_disposed) return;
    revision.value++;
    notifyListeners();
  }

  FileTransferState? _findTransfer(String id) {
    for (final transfer in _transfers) {
      if (transfer.id == id) return transfer;
    }
    return null;
  }

  String _generateId() =>
      List.generate(32, (_) => _random.nextInt(16).toRadixString(16)).join();

  @override
  void dispose() {
    _disposed = true;
    for (final incoming in _incoming.values) {
      incoming.dispose();
      unawaited(incoming.sink?.abort() ?? Future<void>.value());
    }
    for (final sink in _preparedSinks.values) {
      unawaited(sink.abort());
    }
    _incoming.clear();
    _sending.clear();
    _messageSubscription.cancel();
    revision.dispose();
    super.dispose();
  }
}

class _ChunkAckState {
  int sent = 0;
  int acknowledged = 0;
  int target = 0;
  Completer<void>? pending;
}
