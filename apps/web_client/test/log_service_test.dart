import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/services/app_log_service.dart';
import 'package:yonfile_client/ui/widgets/log_viewer_dialog.dart';

void main() {
  setUp(() {
    AppLogService.instance.clear();
  });

  test('AppLogService captures logs and filters correctly', () {
    final logService = AppLogService.instance;

    logService.info('Test info message', tag: 'WebRTC');
    logService.warn('Test warning message', tag: 'Transfer');
    logService.error('Test error message', tag: 'WebRTC', error: 'Connection failed');
    logService.success('Test success message', tag: 'Transfer');

    expect(logService.logs.length, 4);
    expect(logService.logs.first.level, LogLevel.success);
    expect(logService.logs[1].level, LogLevel.error);
    expect(logService.logs[1].details, 'Connection failed');

    final exported = logService.exportText();
    expect(exported.contains('Test info message'), isTrue);
    expect(exported.contains('Connection failed'), isTrue);
  });

  testWidgets('LogViewerDialog renders and displays logs and system diagnostic tags', (
    tester,
  ) async {
    final logService = AppLogService.instance;
    logService.error('WebRTC DataChannel failed', tag: 'WebRTC');
    logService.success('File transfer complete', tag: 'Transfer');

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LogViewerDialog(),
        ),
      ),
    );

    // Verify Title & Diagnostics banner
    expect(find.text('ບັນທຶກ Log & ກວດສອບບັນຫາ'), findsOneWidget);
    expect(find.text('WebRTC DataChannel failed'), findsOneWidget);
    expect(find.text('File transfer complete'), findsOneWidget);

    // Filter to errors only
    await tester.tap(find.text('ສະເພາະ Error'));
    await tester.pump();

    expect(find.text('WebRTC DataChannel failed'), findsOneWidget);
    expect(find.text('File transfer complete'), findsNothing);
  });
}

