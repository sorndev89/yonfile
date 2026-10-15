import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/models/file_transfer_state.dart';

void main() {
  test('transfer history preserves peer identity and terminal state', () {
    final original = FileTransferState(
      id: 'transfer-1',
      fileName: 'report.pdf',
      fileSize: 1200,
      transferred: 1200,
      direction: TransferDirection.send,
      peerName: 'MacBook',
      peerId: 'peer-42',
      status: TransferStatus.completed,
      verified: true,
      startedAt: DateTime.utc(2026, 10, 16),
    );

    final restored = FileTransferState.fromJson(original.toJson());

    expect(restored?.id, original.id);
    expect(restored?.peerId, original.peerId);
    expect(restored?.peerName, original.peerName);
    expect(restored?.status, TransferStatus.completed);
    expect(restored?.verified, isTrue);
    expect(
      restored?.startedAt.millisecondsSinceEpoch,
      original.startedAt.millisecondsSinceEpoch,
    );
  });

  test('invalid transfer history is ignored', () {
    expect(FileTransferState.fromJson({'id': 'broken'}), isNull);
  });
}
