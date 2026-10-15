import 'dart:async';

/// An incoming file offer that is waiting for the receiver's decision.
class IncomingFileOffer {
  IncomingFileOffer({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.fileName,
    required this.fileSize,
  });

  final String id;
  final String peerId;
  final String peerName;
  final String fileName;
  final int fileSize;
  final Completer<bool> response = Completer<bool>();
}
