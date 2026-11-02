import 'dart:async';

/// ໄຟລ໌ໜຶ່ງລາຍການພາຍໃນ batch ທີ່ລໍຖ້າການຍອມຮັບ.
class IncomingBatchFile {
  const IncomingBatchFile({
    required this.id,
    required this.name,
    required this.size,
    this.mime = 'application/octet-stream',
  });

  final String id;
  final String name;
  final int size;
  final String mime;
}

/// Batch ຂອງໄຟລ໌ທີ່ສົ່ງມາພ້ອມກັນ ແລະ ລໍຖ້າການຕັດສິນຄັ້ງດຽວຈາກຜູ້ຮັບ.
class IncomingBatchOffer {
  IncomingBatchOffer({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.files,
  });

  final String id;
  final String peerId;
  final String peerName;
  final List<IncomingBatchFile> files;
  final Completer<bool> response = Completer<bool>();

  int get fileCount => files.length;

  int get totalBytes => files.fold<int>(0, (total, file) => total + file.size);
}
