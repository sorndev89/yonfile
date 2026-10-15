enum TransferStatus {
  idle,
  offering,
  awaitingAccept,
  transferring,
  verifying,
  completed,
  failed,
  cancelled,
}

enum TransferDirection { send, receive }

/// ສະຖານະການໂຍນໄຟລ໌ໜຶ່ງລາຍການ (Sender ຫຼື Receiver).
class FileTransferState {
  final String id;
  final String fileName;
  final int fileSize;
  final int transferred;
  final TransferStatus status;
  final TransferDirection direction;
  final String peerName;
  final String? sha256;
  final bool? verified;
  final String? error;
  final DateTime startedAt;
  final double bytesPerSecond;

  const FileTransferState({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.direction,
    required this.peerName,
    this.transferred = 0,
    this.status = TransferStatus.idle,
    this.sha256,
    this.verified,
    this.error,
    required this.startedAt,
    this.bytesPerSecond = 0,
  });

  double get progress =>
      fileSize <= 0 ? 0 : (transferred / fileSize).clamp(0.0, 1.0);

  int get percent => (progress * 100).round();

  bool get isActive =>
      status == TransferStatus.transferring ||
      status == TransferStatus.offering ||
      status == TransferStatus.awaitingAccept ||
      status == TransferStatus.verifying;

  String get readableSize => formatBytes(fileSize);
  String get readableTransferred => formatBytes(transferred);
  String get readableSpeed => '${formatBytes(bytesPerSecond.round())}/s';

  FileTransferState copyWith({
    int? transferred,
    TransferStatus? status,
    String? sha256,
    bool? verified,
    String? error,
    double? bytesPerSecond,
  }) {
    return FileTransferState(
      id: id,
      fileName: fileName,
      fileSize: fileSize,
      transferred: transferred ?? this.transferred,
      status: status ?? this.status,
      direction: direction,
      peerName: peerName,
      sha256: sha256 ?? this.sha256,
      verified: verified ?? this.verified,
      error: error ?? this.error,
      startedAt: startedAt,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
    );
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
