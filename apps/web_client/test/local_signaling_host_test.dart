import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/services/local_signaling_host.dart';

void main() {
  test('local host registers peers and relays PIN room signals', () async {
    final host = LocalSignalingHost();
    final addresses = await host.start(port: 0);
    expect(addresses, isNotEmpty);

    final first = await WebSocket.connect('ws://127.0.0.1:${host.port}/ws');
    final second = await WebSocket.connect('ws://127.0.0.1:${host.port}/ws');
    final firstMessages = StreamIterator<dynamic>(first);
    final secondMessages = StreamIterator<dynamic>(second);

    try {
      first.add(jsonEncode({'type': 'register', 'name': 'Mac'}));
      second.add(jsonEncode({'type': 'register', 'name': 'Android'}));
      final firstId = (await _nextMessage(
        firstMessages,
        'registered',
      ))['peerId'];
      final secondId = (await _nextMessage(
        secondMessages,
        'registered',
      ))['peerId'];

      first.add(jsonEncode({'type': 'join-pin', 'pin': '123456'}));
      second.add(jsonEncode({'type': 'join-pin', 'pin': '123456'}));
      final room = await _nextMessage(
        secondMessages,
        'peers-updated',
        scope: 'pin',
      );
      expect(room['scope'], 'pin');
      expect((room['peers'] as List).length, 2);

      first.add(
        jsonEncode({
          'type': 'signal',
          'targetId': secondId,
          'payload': {'type': 'offer', 'sdp': 'test-sdp'},
        }),
      );
      final signal = await _nextMessage(secondMessages, 'signal');
      expect(signal['senderId'], firstId);
      expect(signal['payload']['sdp'], 'test-sdp');
    } finally {
      await firstMessages.cancel();
      await secondMessages.cancel();
      await first.close();
      await second.close();
      await host.stop();
    }
  });
}

Future<Map<String, dynamic>> _nextMessage(
  StreamIterator<dynamic> messages,
  String type, {
  String? scope,
}) async {
  while (await messages.moveNext()) {
    final message =
        jsonDecode(messages.current as String) as Map<String, dynamic>;
    if (message['type'] == type &&
        (scope == null || message['scope'] == scope)) {
      return message;
    }
  }
  throw StateError('Connection closed before receiving $type');
}
