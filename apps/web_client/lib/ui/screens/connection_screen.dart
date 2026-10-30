import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/yon_theme.dart';
import '../../models/file_transfer_state.dart';
import '../../models/incoming_file_offer.dart';
import '../../models/peer_device.dart';
import '../../models/picked_file.dart';
import '../../services/file_stream_helper.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/transfer_history_card.dart';
import '../widgets/peer_os_badge.dart';

/// Active peer session UI: connected devices, pending offers and transfers.
class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({
    super.key,
    required this.self,
    required this.peer,
    required this.pendingOffers,
    required this.transfers,
    required this.hasActiveTransfer,
    required this.connectionRoute,
    required this.onSendFile,
    required this.onDropFiles,
    required this.onDropRejected,
    required this.onDisconnect,
    required this.onAccept,
    required this.onReject,
    required this.onCancelTransfer,
    this.onSendText,
    this.showHistory = true,
  });

  final PeerDevice self;
  final PeerDevice peer;
  final List<IncomingFileOffer> pendingOffers;
  final List<FileTransferState> transfers;
  final bool hasActiveTransfer;
  final String connectionRoute;
  final VoidCallback onSendFile;
  final Future<void> Function(List<PickedFile>) onDropFiles;
  final ValueChanged<String> onDropRejected;
  final VoidCallback onDisconnect;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;
  final ValueChanged<String> onCancelTransfer;
  final VoidCallback? onSendText;
  final bool showHistory;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTransfer = transfers.where((transfer) => transfer.isActive);
    final activeTransfers = activeTransfer.toList(growable: false);
    final label = activeTransfer.isEmpty
        ? 'ເຊື່ອມຕໍ່ສຳເລັດ · ພ້ອມໂອນໄຟລ໌'
        : activeTransfer.first.status == TransferStatus.offering
        ? 'ມີໄຟລ໌ລໍຖ້າການຮັບ'
        : 'ກຳລັງໂອນຂໍ້ມູນ';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark
              ? YonTheme.slateDarkCard.withValues(alpha: 0.78)
              : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: YonTheme.yonOrange.withValues(alpha: 0.3)),
        ),
        child: ListView(
          children: [
            Row(
              children: [
                const Icon(Icons.link_rounded, color: YonTheme.emeraldGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ເຊື່ອມຕໍ່ອຸປະກອນ',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ກັບໄປຄົ້ນຫາອຸປະກອນ',
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                label,
                style: TextStyle(
                  color: hasActiveTransfer
                      ? YonTheme.yonOrange
                      : YonTheme.emeraldGreen,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                switch (connectionRoute) {
                  'relay' => 'ເສັ້ນທາງ: ຜ່ານ TURN relay',
                  'direct' => 'ເສັ້ນທາງ: ເຊື່ອມຕໍ່ໂດຍກົງ',
                  _ => 'ກຳລັງກວດສອບເສັ້ນທາງສົ່ງ',
                },
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(child: _ConnectionDevice(peer: self)),
                Expanded(
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: activeTransfer.isEmpty
                            ? 1
                            : activeTransfer.first.status ==
                                      TransferStatus.transferring ||
                                  activeTransfer.first.status ==
                                      TransferStatus.verifying
                            ? activeTransfer.first.progress
                            : null,
                        minHeight: 4,
                        borderRadius: BorderRadius.circular(4),
                        backgroundColor: YonTheme.yonOrange.withValues(
                          alpha: 0.18,
                        ),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          YonTheme.yonOrange,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Icon(
                        activeTransfer.isEmpty
                            ? Icons.check_circle_rounded
                            : activeTransfer.first.direction ==
                                  TransferDirection.send
                            ? Icons.arrow_forward_rounded
                            : Icons.arrow_back_rounded,
                        color: activeTransfer.isEmpty
                            ? YonTheme.emeraldGreen
                            : YonTheme.yonOrange,
                      ),
                    ],
                  ),
                ),
                Expanded(child: _ConnectionDevice(peer: peer)),
              ],
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onSendFile,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('ເລືອກໄຟລ໌ສົ່ງ'),
                ),
                if (onSendText != null)
                  OutlinedButton.icon(
                    onPressed: onSendText,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('ສົ່ງຂໍ້ຄວາມ / ລິ້ງ'),
                  ),
                OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('ຕັດການເຊື່ອມຕໍ່'),
                ),
              ],
            ),
            if (_supportsDesktopDrop(context)) ...[
              const SizedBox(height: 12),
              _ConnectionDropZone(
                isTransferring: hasActiveTransfer,
                onDropFiles: onDropFiles,
                onDropRejected: onDropRejected,
              ),
            ],
            if (pendingOffers.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'ໄຟລ໌ທີ່ລໍຖ້າຮັບ',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final offer in pendingOffers)
                _IncomingOfferCard(
                  offer: offer,
                  onAccept: () => onAccept(offer.id),
                  onReject: () => onReject(offer.id),
                ),
            ],
            if (activeTransfers.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'ສະຖານະການໂອນໄຟລ໌',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TransferSheet(
                transfers: activeTransfers,
                onCancel: onCancelTransfer,
                showHeader: false,
              ),
            ],
            if (showHistory) ...[
              const SizedBox(height: 18),
              TransferHistoryCard(transfers: transfers),
            ],
          ],
        ),
      ),
    );
  }
}

bool _supportsDesktopDrop(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };

class _ConnectionDropZone extends StatefulWidget {
  const _ConnectionDropZone({
    required this.isTransferring,
    required this.onDropFiles,
    required this.onDropRejected,
  });

  final bool isTransferring;
  final Future<void> Function(List<PickedFile>) onDropFiles;
  final ValueChanged<String> onDropRejected;

  @override
  State<_ConnectionDropZone> createState() => _ConnectionDropZoneState();
}

class _ConnectionDropZoneState extends State<_ConnectionDropZone> {
  bool _dragging = false;

  String _guessMime(String name) =>
      switch (name.split('.').last.toLowerCase()) {
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        'pdf' => 'application/pdf',
        'mp4' => 'video/mp4',
        'zip' => 'application/zip',
        _ => 'application/octet-stream',
      };

  Stream<List<int>> _readDroppedFile(
    DropItem item,
    int fileSize,
    Uint8List? bookmark,
  ) async* {
    var hasScope = false;
    try {
      if (bookmark != null && bookmark.isNotEmpty) {
        hasScope = await DesktopDrop.instance
            .startAccessingSecurityScopedResource(bookmark: bookmark);
      }
      yield* FileStreamHelper.streamFile(item, fileSize);
    } finally {
      if (hasScope) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark!,
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (details.files.isEmpty) return;

    final picked = <PickedFile>[];
    var totalBytes = 0;
    for (final item in details.files) {
      final bookmark = item.extraAppleBookmark;
      var hasScope = false;
      try {
        if (bookmark != null && bookmark.isNotEmpty) {
          hasScope = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
        }
        final size = await item.length();
        if (size < 0 || totalBytes + size > AppConfig.maxFileSizeBytes) {
          if (hasScope && bookmark != null) {
            await DesktopDrop.instance.stopAccessingSecurityScopedResource(
              bookmark: bookmark,
            );
          }
          widget.onDropRejected(
            'ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ ${AppConfig.maxFileSizeLabel}',
          );
          return;
        }
        totalBytes += size;
        if (hasScope && bookmark != null) {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
          hasScope = false;
        }
        picked.add(
          PickedFile(
            name: item.name,
            size: size,
            readStream: _readDroppedFile(item, size, bookmark),
            mimeType: item.mimeType ?? _guessMime(item.name),
          ),
        );
      } catch (error) {
        if (hasScope && bookmark != null) {
          try {
            await DesktopDrop.instance.stopAccessingSecurityScopedResource(
              bookmark: bookmark,
            );
          } catch (_) {}
        }
        widget.onDropRejected('ອ່ານໄຟລ໌ ${item.name} ບໍ່ໄດ້: $error');
        return;
      }
    }

    if (picked.isNotEmpty) await widget.onDropFiles(picked);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _dragging
        ? YonTheme.yonOrange
        : YonTheme.yonOrange.withValues(alpha: 0.45);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _handleDrop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: _dragging
              ? YonTheme.yonOrange.withValues(alpha: 0.12)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.025)
                    : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent, width: _dragging ? 2 : 1),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final description = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dragging ? 'ວາງໄຟລ໌ເພື່ອສົ່ງ' : 'ລາກໄຟລ໌ມາວາງທີ່ນີ້',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.isTransferring
                      ? 'ສາມາດວາງໄຟລ໌ເພີ່ມໄດ້ ໃນຂະນະທີ່ກຳລັງໂອນ'
                      : 'ສົ່ງໄປຫາອຸປະກອນທີ່ເຊື່ອມຕໍ່',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            );
            final icon = Icon(
              _dragging
                  ? Icons.file_download_done_rounded
                  : Icons.drive_folder_upload_outlined,
              color: YonTheme.yonOrange,
              size: 28,
            );
            final maxSize = Text(
              'ສູງສຸດ ${AppConfig.maxFileSizeLabel}',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            );
            if (constraints.maxWidth < 460) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(child: description),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: maxSize,
                  ),
                ],
              );
            }
            return Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: description),
                const SizedBox(width: 8),
                maxSize,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ConnectionDevice extends StatelessWidget {
  const _ConnectionDevice({required this.peer});

  final PeerDevice peer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: YonTheme.primaryGradient,
            boxShadow: [
              BoxShadow(
                color: YonTheme.yonOrange.withValues(alpha: 0.22),
                blurRadius: 18,
              ),
            ],
          ),
          child: Icon(peer.icon, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 8),
        Text(
          peer.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          peer.typeLabel,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white54
                : Colors.black54,
          ),
        ),
        const SizedBox(height: 3),
        PeerOsBadge(peer: peer),
      ],
    );
  }
}

class _IncomingOfferCard extends StatelessWidget {
  const _IncomingOfferCard({
    required this.offer,
    required this.onAccept,
    required this.onReject,
  });

  final IncomingFileOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download_rounded, color: YonTheme.yonOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    offer.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'ຈາກ ${offer.peerName} · ${FileTransferState.formatBytes(offer.fileSize)}',
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onReject, child: const Text('ປະຕິເສດ')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('ຮັບໄຟລ໌'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
