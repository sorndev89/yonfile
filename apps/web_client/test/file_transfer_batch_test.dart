import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yonfile_client/controllers/file_transfer_controller.dart';
import 'package:yonfile_client/models/file_transfer_state.dart';
import 'package:yonfile_client/models/peer_device.dart';
import 'package:yonfile_client/models/picked_file.dart';
import 'package:yonfile_client/services/incoming_file_sink.dart';
import 'package:yonfile_client/services/signaling_service.dart';
import 'package:yonfile_client/services/webrtc_service.dart';

const _peerId = 'peer-1';
const _emptySha =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

class _FakeWebRtc extends WebRtcService {
  _FakeWebRtc() : super(SignalingService(url: 'ws://localhost'));

  final _messages = StreamController<PeerMessage>.broadcast();
  final List<Map<String, dynamic>> sentTexts = [];

  @override
  Stream<PeerMessage> get messages => _messages.stream;

  @override
  bool isOpen(String peerId) => true;

  @override
  int bufferedAmount(String peerId) => 0;

  @override
  Future<void> sendText(String peerId, String text) async {
    sentTexts.add(jsonDecode(text) as Map<String, dynamic>);
  }

  @override
  Future<void> sendBinary(String peerId, Uint8List bytes) async {}

  void receive(Map<String, dynamic> data) {
    _messages.add(
      PeerMessage(_peerId, RTCDataChannelMessage(jsonEncode(data))),
    );
  }
}

class _FakeBatchFactory implements IncomingBatchSinkFactory {
  final List<String> created = [];

  @override
  Future<IncomingFileSink> create(String fileName) async {
    created.add(fileName);
    return _FakeSink();
  }

  @override
  Future<void> dispose() async {}
}

class _FakeSink implements IncomingFileSink {
  bool finished = false;
  bool aborted = false;

  @override
  Future<void> write(List<int> bytes) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> finish() async {
    finished = true;
  }

  @override
  Future<void> abort() async {
    aborted = true;
  }
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('one batch accept covers every file without per-file prompts', () async {
    final webrtc = _FakeWebRtc();
    final factory = _FakeBatchFactory();
    final controller = FileTransferController(
      webrtc: webrtc,
      peerName: (_) => 'Sender',
      batchSinkFactoryProvider: () async => factory,
    );

    final files = [
      for (var i = 0; i < 25; i++)
        {
          'id': 'file-$i',
          'name': 'file_$i.txt',
          'size': 0,
          'mime': 'text/plain',
        },
    ];
    webrtc.receive({'type': 'offer-batch', 'id': 'batch-1', 'files': files});
    await _pump();

    expect(controller.pendingIncomingBatches, hasLength(1));
    expect(controller.pendingIncomingBatches['batch-1']!.fileCount, 25);
    expect(controller.pendingIncomingOffers, isEmpty);

    await controller.acceptIncomingBatch('batch-1');
    await _pump();

    expect(controller.pendingIncomingBatches, isEmpty);
    expect(
      webrtc.sentTexts.any((message) => message['type'] == 'accept-batch'),
      isTrue,
    );

    for (var i = 0; i < 25; i++) {
      webrtc.receive({
        'type': 'offer-file',
        'id': 'file-$i',
        'name': 'file_$i.txt',
        'size': 0,
        'mime': 'text/plain',
        'batchId': 'batch-1',
      });
      await _pump();

      expect(controller.pendingIncomingOffers, isEmpty);
      expect(
        webrtc.sentTexts.any(
          (message) =>
              message['type'] == 'accept-file' && message['id'] == 'file-$i',
        ),
        isTrue,
      );

      webrtc.receive({'type': 'eof', 'id': 'file-$i', 'sha256': _emptySha});
      await _pump();
    }

    final completed = controller.transfers.where(
      (transfer) => transfer.status == TransferStatus.completed,
    );
    expect(completed, hasLength(25));
    expect(factory.created, hasLength(25));
    controller.dispose();
  });

  test('rejecting a batch rejects every file at once', () async {
    final webrtc = _FakeWebRtc();
    final controller = FileTransferController(
      webrtc: webrtc,
      peerName: (_) => 'Sender',
      batchSinkFactoryProvider: () async => _FakeBatchFactory(),
    );

    webrtc.receive({
      'type': 'offer-batch',
      'id': 'batch-2',
      'files': [
        {'id': 'a', 'name': 'a.txt', 'size': 1},
        {'id': 'b', 'name': 'b.txt', 'size': 1},
      ],
    });
    await _pump();

    controller.rejectIncomingBatch('batch-2');
    await _pump();

    expect(controller.pendingIncomingBatches, isEmpty);
    expect(
      webrtc.sentTexts.any((message) => message['type'] == 'reject-batch'),
      isTrue,
    );
    final cancelled = controller.transfers.where(
      (transfer) => transfer.status == TransferStatus.cancelled,
    );
    expect(cancelled, hasLength(2));
    controller.dispose();
  });

  test('batch total above the size cap is rejected up front', () async {
    final webrtc = _FakeWebRtc();
    final controller = FileTransferController(
      webrtc: webrtc,
      peerName: (_) => 'Sender',
      batchSinkFactoryProvider: () async => _FakeBatchFactory(),
    );

    final sixGb = 6 * 1024 * 1024 * 1024;
    webrtc.receive({
      'type': 'offer-batch',
      'id': 'batch-3',
      'files': [
        {'id': 'a', 'name': 'a.bin', 'size': sixGb},
        {'id': 'b', 'name': 'b.bin', 'size': sixGb},
      ],
    });
    await _pump();

    expect(controller.pendingIncomingBatches, isEmpty);
    expect(
      webrtc.sentTexts.any((message) => message['type'] == 'reject-batch'),
      isTrue,
    );
    controller.dispose();
  });

  test(
    'sender offers a batch once then sends files under it on accept',
    () async {
      final webrtc = _FakeWebRtc();
      final controller = FileTransferController(
        webrtc: webrtc,
        peerName: (_) => 'Receiver',
        batchSinkFactoryProvider: () async => _FakeBatchFactory(),
      );
      const peer = PeerDevice(
        id: _peerId,
        name: 'Receiver',
        deviceType: PeerDeviceType.desktop,
        scope: PeerScope.lan,
      );

      final future = controller.sendFiles(peer, [
        PickedFile(name: 'a.txt', size: 3, bytes: Uint8List(3)),
        PickedFile(name: 'b.txt', size: 3, bytes: Uint8List(3)),
      ]);
      await _pump();

      final batchOffer = webrtc.sentTexts.singleWhere(
        (message) => message['type'] == 'offer-batch',
      );
      expect(batchOffer['files'], hasLength(2));
      final batchId = batchOffer['id'] as String;
      final fileIds = [
        for (final file in batchOffer['files'] as List)
          (file as Map)['id'] as String,
      ];

      webrtc.receive({'type': 'accept-batch', 'id': batchId});
      await _pump();

      final firstOffer = webrtc.sentTexts.singleWhere(
        (message) =>
            message['type'] == 'offer-file' && message['id'] == fileIds.first,
      );
      expect(firstOffer['batchId'], batchId);

      webrtc.receive({'type': 'reject-file', 'id': fileIds.first});
      await _pump();

      final secondOffer = webrtc.sentTexts.singleWhere(
        (message) =>
            message['type'] == 'offer-file' && message['id'] == fileIds.last,
      );
      expect(secondOffer['batchId'], batchId);

      webrtc.receive({'type': 'reject-file', 'id': fileIds.last});
      await future;

      final cancelled = controller.transfers.where(
        (transfer) => transfer.status == TransferStatus.cancelled,
      );
      expect(cancelled, hasLength(2));
      controller.dispose();
    },
  );

  test('legacy single-file offer still waits for an explicit accept', () async {
    final webrtc = _FakeWebRtc();
    final controller = FileTransferController(
      webrtc: webrtc,
      peerName: (_) => 'Sender',
      batchSinkFactoryProvider: () async => _FakeBatchFactory(),
    );

    webrtc.receive({
      'type': 'offer-file',
      'id': 'single-1',
      'name': 'single.txt',
      'size': 0,
      'mime': 'text/plain',
    });
    await _pump();

    expect(controller.pendingIncomingOffers, hasLength(1));
    expect(
      webrtc.sentTexts.any((message) => message['type'] == 'accept-file'),
      isFalse,
    );
    controller.dispose();
  });
}
