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
  final String? peerId;
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
    this.peerId,
    this.transferred = 0,
    this.status = TransferStatus.idle,
    this.sha256,
    this.verified,
    this.error,
    required this.startedAt,
    this.bytesPerSecond = 0,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'fileSize': fileSize,
    'transferred': transferred,
    'status': status.name,
    'direction': direction.name,
    'peerName': peerName,
    'peerId': peerId,
    'sha256': sha256,
    'verified': verified,
    'error': error,
    'startedAt': startedAt.millisecondsSinceEpoch,
    'bytesPerSecond': bytesPerSecond,
  };

  static FileTransferState? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final statusName = value['status'];
    final directionName = value['direction'];
    final startedAt = value['startedAt'];
    final fileSize = value['fileSize'];
    if (value['id'] is! String ||
        value['fileName'] is! String ||
        fileSize is! int ||
        value['peerName'] is! String ||
        startedAt is! int) {
      return null;
    }
    final status = TransferStatus.values.where(
      (item) => item.name == statusName,
    );
    final direction = TransferDirection.values.where(
      (item) => item.name == directionName,
    );
    if (status.isEmpty ||
        direction.isEmpty ||
        status.first == TransferStatus.idle) {
      return null;
    }
    return FileTransferState(
      id: value['id'] as String,
      fileName: value['fileName'] as String,
      fileSize: fileSize,
      transferred: value['transferred'] is int
          ? value['transferred'] as int
          : 0,
      status: status.first,
      direction: direction.first,
      peerName: value['peerName'] as String,
      peerId: value['peerId'] is String ? value['peerId'] as String : null,
      sha256: value['sha256'] is String ? value['sha256'] as String : null,
      verified: value['verified'] is bool ? value['verified'] as bool : null,
      error: value['error'] is String ? value['error'] as String : null,
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
      bytesPerSecond: value['bytesPerSecond'] is num
          ? (value['bytesPerSecond'] as num).toDouble()
          : 0,
    );
  }

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
      peerId: peerId,
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
