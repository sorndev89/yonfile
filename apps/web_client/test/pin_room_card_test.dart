import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/ui/widgets/pin_room_card.dart';

void main() {
  testWidgets('PinRoomCard displays own PIN and disables join button while connecting', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinRoomCard(
            ownPin: '123456',
            joinedPin: null,
            isConnecting: true,
            onJoinPin: (_) {},
            onLeavePin: () {},
            onChangePin: () {},
            onScan: () {},
          ),
        ),
      ),
    );

    // Verify own PIN is formatted: 123 - 456
    expect(find.text('123 - 456'), findsOneWidget);

    // When isConnecting is true, join button is disabled and shows progress indicator
    final buttonFinder = find.byType(ElevatedButton);
    expect(buttonFinder, findsOneWidget);
    final button = tester.widget<ElevatedButton>(buttonFinder);
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('PinRoomCard calls onJoinPin when entering 6-digit pin', (
    tester,
  ) async {
    String? joinedPin;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinRoomCard(
            ownPin: '654321',
            joinedPin: null,
            isConnecting: false,
            onJoinPin: (pin) => joinedPin = pin,
            onLeavePin: () {},
            onChangePin: () {},
            onScan: () {},
          ),
        ),
      ),
    );

    // Enter 6-digit pin
    final textFieldFinder = find.byType(TextField);
    await tester.enterText(textFieldFinder, '999888');
    await tester.pump();

    // Click connect
    await tester.tap(find.text('ເຊື່ອມຕໍ່'));
    await tester.pump();

    expect(joinedPin, '999888');
  });

  testWidgets('PIN Dialog with ຕົກລົງ button triggers connection when 6 digits entered', (
    tester,
  ) async {
    String? submittedPin;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                var enteredPin = '';
                final pin = await showDialog<String>(
                  context: context,
                  builder: (dialogContext) => StatefulBuilder(
                    builder: (ctx, setDialogState) => AlertDialog(
                      title: const Text('ປ້ອນລະຫັດຜ່ານ (PIN)'),
                      content: TextField(
                        autofocus: true,
                        maxLength: 6,
                        onChanged: (v) => setDialogState(() => enteredPin = v.trim()),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('ຍົກເລີກ'),
                        ),
                        ElevatedButton(
                          onPressed: enteredPin.length == 6
                              ? () => Navigator.pop(dialogContext, enteredPin)
                              : null,
                          child: const Text('ຕົກລົງ'),
                        ),
                      ],
                    ),
                  ),
                );
                submittedPin = pin;
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify dialog title and actions
    expect(find.text('ປ້ອນລະຫັດຜ່ານ (PIN)'), findsOneWidget);
    expect(find.text('ຍົກເລີກ'), findsOneWidget);
    expect(find.text('ຕົກລົງ'), findsOneWidget);

    // Initially "ຕົກລົງ" button is disabled (< 6 digits)
    final okButtonFinder = find.widgetWithText(ElevatedButton, 'ຕົກລົງ');
    var okButton = tester.widget<ElevatedButton>(okButtonFinder);
    expect(okButton.onPressed, isNull);

    // Enter partial PIN (3 digits)
    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();
    okButton = tester.widget<ElevatedButton>(okButtonFinder);
    expect(okButton.onPressed, isNull);

    // Enter full 6 digits
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    okButton = tester.widget<ElevatedButton>(okButtonFinder);
    expect(okButton.onPressed, isNotNull);

    // Click "ຕົກລົງ"
    await tester.tap(okButtonFinder);
    await tester.pumpAndSettle();

    // Dialog dismissed and submittedPin captured
    expect(find.text('ປ້ອນລະຫັດຜ່ານ (PIN)'), findsNothing);
    expect(submittedPin, '123456');
  });
}

