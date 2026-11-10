import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_config.dart';
import '../models/file_transfer_state.dart';
import '../models/incoming_batch_offer.dart';
import '../models/incoming_file_offer.dart';
import '../models/peer_device.dart';
import '../models/picked_file.dart';
import '../services/app_log_service.dart';
import '../services/file_chunker_service.dart';
import '../services/incoming_file_sink.dart';
import '../services/webrtc_service.dart';

/// Owns transfer protocol state and coordinates file messages over WebRTC.
class FileTransferController extends ChangeNotifier {
  FileTransferController({
    required WebRtcService webrtc,
    required String Function(String peerId) peerName,
    this.onIncomingText,
    Future<IncomingBatchSinkFactory?> Function()? batchSinkFactoryProvider,
  }) : _webrtc = webrtc,
       _peerName = peerName,
       _batchSinkFactoryProvider =
           batchSinkFactoryProvider ?? createIncomingBatchSinkFactory {
    _messageSubscription = _webrtc.messages.listen(handlePeerMessage);
    _historyReady = _restoreHistory();
  }

  static const String _historyKey = 'file_transfer_history_v1';

  final WebRtcService _webrtc;
  final String Function(String peerId) _peerName;
  final void Function(String peerId, String text)? onIncomingText;
  final Future<IncomingBatchSinkFactory?> Function() _batchSinkFactoryProvider;
  final FileChunkerService _chunker = FileChunkerService();
  final math.Random _random = math.Random.secure();

  final List<FileTransferState> _transfers = [];
  final Map<String, Uint8List> _outgoingBytes = {};
  final Map<String, Completer<bool>> _pendingAccepts = {};
  final Map<String, Completer<bool>> _pendingBatchAccepts = {};
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
  final Map<String, IncomingBatchOffer> _pendingIncomingBatches = {};
  final Map<String, IncomingBatchSinkFactory> _batchSinkFactories = {};
  final Map<String, Set<String>> _batchFileIds = {};
  final Map<String, String> _fileBatches = {};
  final Map<String, int> _batchRemaining = {};
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
  Map<String, IncomingBatchOffer> get pendingIncomingBatches =>
      Map.unmodifiable(_pendingIncomingBatches);
  int get incomingReservedBytes =>
      _incoming.values.fold(0, (total, file) => total + file.fileSize);
  int get _pendingOfferBytes => _pendingIncomingOffers.values.fold(
    0,
    (total, offer) => total + offer.fileSize,
  );
  int get _pendingBatchBytes => _pendingIncomingBatches.values.fold(
    0,
    (total, batch) => total + batch.totalBytes,
  );

  List<FileTransferState> transfersForPeer(String peerId, String peerName) =>
      _transfers
          .where(
            (transfer) =>
                transfer.peerId == peerId ||
                (transfer.peerId == null && transfer.peerName == peerName) ||
                _transferPeers[transfer.id] == peerId ||
                _pendingIncomingOffers[transfer.id]?.peerId == peerId ||
                _pendingIncomingBatches.values.any(
                  (batch) =>
                      batch.peerId == peerId &&
                      batch.files.any((file) => file.id == transfer.id),
                ),
          )
          .toList();

  bool hasActiveTransferForPeer(String peerId) => _transfers.any(
    (transfer) =>
        transfer.isActive &&
        (_transferPeers[transfer.id] == peerId ||
            _pendingIncomingOffers[transfer.id]?.peerId == peerId ||
            _pendingIncomingBatches.values.any(
              (batch) => batch.peerId == peerId,
            )),
  );

  Future<void> sendFiles(PeerDevice peer, List<PickedFile> files) async {
    if (files.length <= 1) {
      for (final file in files) {
        await _sendSingleFile(peer, file);
      }
      return;
    }
    await _sendBatch(peer, files);
  }

  /// ສົ່ງຫຼາຍໄຟລ໌ເປັນ batch: ຜູ້ຮັບກົດຍອມຮັບພຽງຄັ້ງດຽວ ແລ້ວໄຟລ໌ທັງໝົດ
  /// ຈະຖືກຮັບແບບອັດຕະໂນມັດ (ຍັງສົ່ງທີລະໄຟລ໌ເພື່ອຄວບຄຸມ backpressure).
  Future<void> _sendBatch(PeerDevice peer, List<PickedFile> files) async {
    final batchId = _generateId();
    final entries = [for (final file in files) (id: _generateId(), file: file)];
    final completer = Completer<bool>();
    _pendingBatchAccepts[batchId] = completer;

    for (final entry in entries) {
      _sending.add(entry.id);
      _transferPeers[entry.id] = peer.id;
      _upsertTransfer(
        FileTransferState(
          id: entry.id,
          fileName: entry.file.name,
          fileSize: entry.file.size,
          direction: TransferDirection.send,
          peerName: peer.name,
          peerId: peer.id,
          status: TransferStatus.awaitingAccept,
          startedAt: DateTime.now(),
        ),
      );
    }

    try {
      await _webrtc.sendText(
        peer.id,
        jsonEncode({
          'type': 'offer-batch',
          'id': batchId,
          'files': [
            for (final entry in entries)
              {
                'id': entry.id,
                'name': entry.file.name,
                'size': entry.file.size,
                'mime': entry.file.mimeType,
              },
          ],
        }),
      );
      final accepted = await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => false,
      );
      if (!accepted) {
        for (final entry in entries) {
          _updateTransfer(
            entry.id,
            (transfer) => transfer.copyWith(status: TransferStatus.cancelled),
          );
          _sending.remove(entry.id);
          _transferPeers.remove(entry.id);
        }
        return;
      }

      for (final entry in entries) {
        await _sendSingleFile(peer, entry.file, id: entry.id, batchId: batchId);
      }
    } catch (error) {
      for (final entry in entries) {
        _updateTransfer(
          entry.id,
          (transfer) =>
              transfer.copyWith(status: TransferStatus.failed, error: '$error'),
        );
        _sending.remove(entry.id);
        _transferPeers.remove(entry.id);
      }
    } finally {
      _pendingBatchAccepts.remove(batchId);
    }
  }

  Future<void> _sendSingleFile(
    PeerDevice peer,
    PickedFile file, {
    String? id,
    String? batchId,
  }) async {
    final transferId = id ?? _generateId();
    final completer = Completer<bool>();
    _pendingAccepts[transferId] = completer;
    if (file.bytes != null) _outgoingBytes[transferId] = file.bytes!;
    _sending.add(transferId);
    _transferPeers[transferId] = peer.id;
    _upsertTransfer(
      FileTransferState(
        id: transferId,
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
      AppLogService.instance.info(
        'ສະເໜີສົ່ງໄຟລ໌: ${file.name} (${file.readableSize}) ຫາ ${peer.name}',
        tag: 'Transfer',
      );
      await _webrtc.sendText(
        peer.id,
        jsonEncode({
          'type': 'offer-file',
          'id': transferId,
          'name': file.name,
          'size': file.size,
          'mime': file.mimeType,
          'batchId': ?batchId,
        }),
      );
      final accepted = await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => false,
      );
      if (!accepted) {
        AppLogService.instance.warn(
          '${peer.name} ປະຕິເສດ ຫຼື ໝົດເວລາການຮັບ: ${file.name}',
          tag: 'Transfer',
        );
        _updateTransfer(
          transferId,
          (t) => t.copyWith(status: TransferStatus.cancelled),
        );
        return;
      }

      AppLogService.instance.info(
        '${peer.name} ຍອມຮັບແລ້ວ! ເລີ່ມສົ່ງຂໍ້ມູນ: ${file.name}',
        tag: 'Transfer',
      );
      _updateTransfer(
        transferId,
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
            transferId,
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
              sendChunk: (chunk) =>
                  _sendBinaryChunk(transferId, peer.id, chunk),
              bufferedAmount: () => _webrtc.bufferedAmount(peer.id),
              onProgress: onProgress,
              isCancelled: () => _cancelled.contains(transferId),
              isChannelOpen: () => _webrtc.isOpen(peer.id),
            )
          : await _sendBytesWithProgress(transferId, peer, file, onProgress);
      await _flushSendWindow(transferId, peer.id);
      if (_cancelled.contains(transferId)) {
        throw const TransferCancelledException();
      }
      _updateTransfer(transferId, (t) => t.copyWith(sha256: sha));
      final completion = Completer<bool>();
      _pendingCompletions[transferId] = completion;
      _updateTransfer(
        transferId,
        (t) => t.copyWith(
          status: TransferStatus.verifying,
          transferred: file.size,
        ),
      );
      await _webrtc.sendText(
        peer.id,
        jsonEncode({'type': 'eof', 'id': transferId, 'sha256': sha}),
      );
      final completed = await completion.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () => false,
      );
      if (!completed) {
        AppLogService.instance.error(
          'ບໍ່ໄດ້ຮັບຄຳຢືນຢັນຈາກ ${peer.name} ສຳລັບໄຟລ໌ ${file.name}',
          tag: 'Transfer',
        );
        _updateTransfer(
          transferId,
          (t) => t.copyWith(
            status: TransferStatus.failed,
            error: 'ບໍ່ໄດ້ຮັບຄຳຢືນຢັນຈາກອຸປະກອນປາຍທາງ',
          ),
        );
      } else {
        AppLogService.instance.success(
          'ໂອນໄຟລ໌ສຳເລັດສົມບູນ: ${file.name}',
          tag: 'Transfer',
        );
      }
    } on TransferCancelledException {
      AppLogService.instance.warn(
        'ການໂອນຖືກຍົກເລີກ: ${file.name}',
        tag: 'Transfer',
      );
      _updateTransfer(
        transferId,
        (t) => t.copyWith(status: TransferStatus.cancelled),
      );
      if (_webrtc.isOpen(peer.id)) {
        await _webrtc.sendText(
          peer.id,
          jsonEncode({'type': 'cancel-file', 'id': transferId}),
        );
      }
    } catch (error) {
      AppLogService.instance.error(
        'ໂອນໄຟລ໌ບໍ່ສຳເລັດ: ${file.name} - $error',
        tag: 'Transfer',
        error: error,
      );
      if (_webrtc.isOpen(peer.id)) {
        try {
          await _webrtc.sendText(
            peer.id,
            jsonEncode({'type': 'cancel-file', 'id': transferId}),
          );
        } catch (_) {}
      }
      _updateTransfer(
        transferId,
        (t) => t.copyWith(
          status: TransferStatus.failed,
          error: error is TransferStalledException
              ? 'ການສົ່ງຢຸດຊະງັກ ກະລຸນາລອງສົ່ງໃໝ່'
              : '$error',
        ),
      );
    } finally {
      _outgoingBytes.remove(transferId);
      _sending.remove(transferId);
      final waitingForCompletion = _transfers.any(
        (transfer) =>
            transfer.id == transferId &&
            transfer.status == TransferStatus.verifying,
      );
      if (!waitingForCompletion) _transferPeers.remove(transferId);
      _cancelled.remove(transferId);
      _pendingAccepts.remove(transferId);
      _pendingCompletions.remove(transferId);
      _chunkAckStates.remove(transferId);
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
      case 'offer-batch':
        _onOfferBatch(message.peerId, data);
      case 'accept-batch':
        final id = data['id'];
        final pending = id is String ? _pendingBatchAccepts[id] : null;
        if (pending != null && !pending.isCompleted) pending.complete(true);
      case 'reject-batch':
        final id = data['id'];
        final pending = id is String ? _pendingBatchAccepts[id] : null;
        if (pending != null && !pending.isCompleted) pending.complete(false);
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
    for (final offer
        in _pendingIncomingBatches.values
            .where((offer) => offer.peerId == peerId)
            .toList()) {
      if (!offer.response.isCompleted) offer.response.complete(false);
      _pendingIncomingBatches.remove(offer.id);
    }
    for (final entry in _batchFileIds.entries.toList()) {
      if (entry.value.any((id) => _transferPeers[id] == peerId)) {
        _batchFileIds.remove(entry.key);
        _batchRemaining.remove(entry.key);
        for (final id in entry.value) {
          _fileBatches.remove(id);
        }
        final factory = _batchSinkFactories.remove(entry.key);
        if (factory != null) unawaited(factory.dispose());
      }
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

  Future<void> _onOfferBatch(String peerId, Map<String, dynamic> data) async {
    final batchId = data['id'] is String ? data['id'] as String : '';
    final rawFiles = data['files'];
    final peerName = _peerName(peerId);
    String? rejectionReason;
    final files = <IncomingBatchFile>[];

    if (batchId.isEmpty ||
        batchId.length > 80 ||
        rawFiles is! List ||
        rawFiles.isEmpty) {
      rejectionReason = 'ຂໍ້ມູນໄຟລ໌ບໍ່ຄົບຖ້ວນ';
    } else {
      final seenIds = <String>{};
      for (final raw in rawFiles) {
        if (raw is! Map) {
          rejectionReason = 'ຂໍ້ມູນໄຟລ໌ບໍ່ຄົບຖ້ວນ';
          break;
        }
        final id = raw['id'] is String ? raw['id'] as String : '';
        final rawName = raw['name'] is String ? raw['name'] as String : 'file';
        final name = rawName
            .replaceAll(RegExp(r'[\\/\u0000-\u001f]'), '_')
            .trim();
        final size = raw['size'] is num ? (raw['size'] as num).toInt() : -1;
        final mime = raw['mime'] is String
            ? raw['mime'] as String
            : 'application/octet-stream';
        if (id.isEmpty ||
            id.length > 80 ||
            name.isEmpty ||
            name.length > 255 ||
            size < 0 ||
            !seenIds.add(id)) {
          rejectionReason = 'ຂໍ້ມູນໄຟລ໌ບໍ່ຄົບຖ້ວນ';
          break;
        }
        files.add(
          IncomingBatchFile(id: id, name: name, size: size, mime: mime),
        );
      }
    }

    final totalBytes = files.fold<int>(0, (total, file) => total + file.size);
    if (rejectionReason == null) {
      if (totalBytes > AppConfig.maxFileSizeBytes ||
          incomingReservedBytes +
                  _pendingOfferBytes +
                  _pendingBatchBytes +
                  totalBytes >
              AppConfig.maxFileSizeBytes) {
        rejectionReason = 'ໄຟລ໌ໃຫຍ່ເກີນຂີດຈຳກັດ';
      } else if (_activeIncomingId.containsKey(peerId) ||
          _pendingIncomingOffers.values.any(
            (offer) => offer.peerId == peerId,
          ) ||
          _batchFileIds.entries.any(
            (entry) => entry.value.any((id) => _transferPeers[id] == peerId),
          )) {
        rejectionReason = 'ມີການຮັບໄຟລ໌ອື່ນຄ້າງຢູ່';
      }
    }

    if (rejectionReason != null) {
      for (final file in files) {
        _upsertTransfer(
          FileTransferState(
            id: file.id,
            fileName: file.name,
            fileSize: file.size,
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
          jsonEncode({'type': 'reject-batch', 'id': batchId}),
        );
      }
      return;
    }
    if (_pendingIncomingBatches.containsKey(batchId)) return;

    final offer = IncomingBatchOffer(
      id: batchId,
      peerId: peerId,
      peerName: peerName,
      files: files,
    );
    _pendingIncomingBatches[batchId] = offer;
    for (final file in files) {
      _transferPeers[file.id] = peerId;
      _upsertTransfer(
        FileTransferState(
          id: file.id,
          fileName: file.name,
          fileSize: file.size,
          direction: TransferDirection.receive,
          peerName: peerName,
          peerId: peerId,
          status: TransferStatus.offering,
          startedAt: DateTime.now(),
        ),
      );
    }

    final accepted = await offer.response.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () => false,
    );
    _pendingIncomingBatches.remove(batchId);
    if (!accepted) {
      final factory = _batchSinkFactories.remove(batchId);
      if (factory != null) unawaited(factory.dispose());
      for (final file in files) {
        _updateTransfer(
          file.id,
          (transfer) => transfer.copyWith(status: TransferStatus.cancelled),
        );
        _transferPeers.remove(file.id);
      }
      if (_webrtc.isOpen(peerId)) {
        await _webrtc.sendText(
          peerId,
          jsonEncode({'type': 'reject-batch', 'id': batchId}),
        );
      }
      return;
    }

    if (!_webrtc.isOpen(peerId)) {
      final factory = _batchSinkFactories.remove(batchId);
      if (factory != null) unawaited(factory.dispose());
      _batchFileIds.remove(batchId);
      _batchRemaining.remove(batchId);
      for (final file in files) {
        _fileBatches.remove(file.id);
        _updateTransfer(
          file.id,
          (transfer) => transfer.copyWith(
            status: TransferStatus.failed,
            error: 'ການເຊື່ອມຕໍ່ຖືກຕັດກ່ອນເລີ່ມຮັບໄຟລ໌',
          ),
        );
      }
      return;
    }
    await _webrtc.sendText(
      peerId,
      jsonEncode({'type': 'accept-batch', 'id': batchId}),
    );
    _batchFileIds[batchId] = files.map((file) => file.id).toSet();
    _batchRemaining[batchId] = files.length;
    for (final file in files) {
      _fileBatches[file.id] = batchId;
    }
  }

  Future<void> _onOfferFile(String peerId, Map<String, dynamic> data) async {
    final id = data['id'] is String ? data['id'] as String : '';
    final rawBatchId = data['batchId'];
    final batchId = rawBatchId is String ? rawBatchId : null;
    final isBatchFile =
        batchId != null && _batchFileIds[batchId]?.contains(id) == true;
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
    } else if (size > AppConfig.maxFileSizeBytes) {
      rejectionReason = 'ໄຟລ໌ໃຫຍ່ເກີນຂີດຈຳກັດ';
    } else if (isBatchFile && _transferPeers[id] != peerId) {
      rejectionReason = 'ຂໍ້ມູນໄຟລ໌ບໍ່ຄົບຖ້ວນ';
    } else if (!isBatchFile &&
        (incomingReservedBytes +
                    _pendingOfferBytes +
                    _pendingBatchBytes +
                    size >
                AppConfig.maxFileSizeBytes ||
            _pendingIncomingOffers.length >= 4)) {
      rejectionReason = 'ໄຟລ໌ໃຫຍ່ເກີນຂີດຈຳກັດ';
    } else if (_activeIncomingId.containsKey(peerId) ||
        (!isBatchFile &&
            _pendingIncomingOffers.values.any(
              (offer) => offer.peerId == peerId,
            ))) {
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
      if (isBatchFile) _completeBatchFile(id);
      if (_webrtc.isOpen(peerId)) {
        await _webrtc.sendText(
          peerId,
          jsonEncode({'type': 'reject-file', 'id': id}),
        );
      }
      return;
    }

    if (isBatchFile) {
      final factory = _batchSinkFactories[batchId];
      if (factory == null) {
        await _rejectIncomingFile(peerId, id, 'ບໍ່ສາມາດເປີດບ່ອນບັນທຶກໄຟລ໌ໄດ້');
        return;
      }
      IncomingFileSink sink;
      try {
        sink = await factory.create(name);
      } catch (error) {
        debugPrint('Unable to prepare incoming batch file: $error');
        await _rejectIncomingFile(peerId, id, 'ບໍ່ສາມາດເປີດບ່ອນບັນທຶກໄຟລ໌ໄດ້');
        return;
      }
      if (!_webrtc.isOpen(peerId)) {
        await sink.abort();
        _updateTransfer(
          id,
          (transfer) => transfer.copyWith(
            status: TransferStatus.failed,
            error: 'ການເຊື່ອມຕໍ່ຖືກຕັດກ່ອນເລີ່ມຮັບໄຟລ໌',
          ),
        );
        _completeBatchFile(id);
        return;
      }
      await _activateIncoming(peerId, id, name, size, peerName, sink);
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
    await _activateIncoming(peerId, id, name, size, peerName, sink);
  }

  Future<void> _activateIncoming(
    String peerId,
    String id,
    String name,
    int size,
    String peerName,
    IncomingFileSink sink,
  ) async {
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
      return;
    }
    _incoming.remove(id);
    _activeIncomingId.remove(peerId);
    _transferPeers.remove(id);
    await sink.abort();
    _updateTransfer(
      id,
      (t) => t.copyWith(
        status: TransferStatus.failed,
        error: 'ການເຊື່ອມຕໍ່ຖືກຕັດກ່ອນເລີ່ມຮັບໄຟລ໌',
      ),
    );
    _completeBatchFile(id);
  }

  Future<void> _rejectIncomingFile(
    String peerId,
    String id,
    String error,
  ) async {
    _updateTransfer(
      id,
      (transfer) =>
          transfer.copyWith(status: TransferStatus.failed, error: error),
    );
    _completeBatchFile(id);
    if (_webrtc.isOpen(peerId)) {
      await _webrtc.sendText(
        peerId,
        jsonEncode({'type': 'reject-file', 'id': id}),
      );
    }
  }

  void _completeBatchFile(String fileId) {
    final batchId = _fileBatches.remove(fileId);
    if (batchId == null) return;
    final ids = _batchFileIds[batchId];
    if (ids == null) return;
    ids.remove(fileId);
    final remaining = (_batchRemaining[batchId] ?? ids.length + 1) - 1;
    _batchRemaining[batchId] = remaining < 0 ? 0 : remaining;
    if (ids.isEmpty) {
      _batchFileIds.remove(batchId);
      _batchRemaining.remove(batchId);
      final factory = _batchSinkFactories.remove(batchId);
      if (factory != null) unawaited(factory.dispose());
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
    AppLogService.instance.error(
      'ການຮັບໄຟລ໌ລົ້ມເຫຼວ ($id): $error',
      tag: 'Transfer',
    );
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
    _completeBatchFile(id);
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
    if (completed) {
      AppLogService.instance.success(
        'ຮັບໄຟລ໌ ແລະ ກວດສອບ SHA-256 ສຳເລັດ: ${incoming.fileName}',
        tag: 'Transfer',
      );
    } else if (!verified) {
      AppLogService.instance.error(
        'ກວດສອບ SHA-256 ບໍ່ກົງກັນ: ${incoming.fileName} (ຄາດຫວັງ: $expected)',
        tag: 'Transfer',
      );
    } else {
      AppLogService.instance.error(
        'ບັນທຶກໄຟລ໌ລົງ disk ບໍ່ສຳເລັດ ຫຼືຖືກຍົກເລີກ: ${incoming.fileName}',
        tag: 'Transfer',
      );
    }
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
    _completeBatchFile(id);
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
    _completeBatchFile(id);
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
    _completeBatchFile(id);
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

  Future<void> acceptIncomingBatch(String id) async {
    final offer = _pendingIncomingBatches[id];
    if (offer == null || offer.response.isCompleted) return;
    try {
      final factory = await _batchSinkFactoryProvider();
      if (factory == null) {
        if (!offer.response.isCompleted) offer.response.complete(false);
        return;
      }
      if (offer.response.isCompleted || _pendingIncomingBatches[id] != offer) {
        await factory.dispose();
        return;
      }
      _batchSinkFactories[id] = factory;
      _batchFileIds[id] = offer.files.map((file) => file.id).toSet();
      _batchRemaining[id] = offer.files.length;
      for (final file in offer.files) {
        _fileBatches[file.id] = id;
      }
      offer.response.complete(true);
    } catch (error) {
      debugPrint('Unable to prepare incoming batch: $error');
      if (!offer.response.isCompleted) offer.response.complete(false);
    }
  }

  void rejectIncomingBatch(String id) {
    final offer = _pendingIncomingBatches[id];
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
    _completeBatchFile(id);
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
    for (final factory in _batchSinkFactories.values) {
      unawaited(factory.dispose());
    }
    _incoming.clear();
    _batchSinkFactories.clear();
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
