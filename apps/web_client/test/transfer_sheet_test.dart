import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/models/file_transfer_state.dart';
import 'package:yonfile_client/ui/widgets/transfer_sheet.dart';

void main() {
  testWidgets('transfer details fit on a narrow phone screen', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransferSheet(
            transfers: [
              FileTransferState(
                id: 'transfer-1',
                fileName: 'yonfile-mobile-release-build.apk',
                fileSize: 129 * 1024 * 1024,
                transferred: 64 * 1024 * 1024,
                status: TransferStatus.transferring,
                direction: TransferDirection.send,
                peerName: 'MacM4Pro',
                startedAt: DateTime(2026),
                bytesPerSecond: 1.9 * 1024 * 1024,
              ),
            ],
            onCancel: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('64.0 MB / 129.0 MB'), findsOneWidget);
    expect(find.textContaining('1.9 MB/s'), findsOneWidget);
  });
}
