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
}

