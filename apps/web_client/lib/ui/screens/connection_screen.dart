import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';
import '../../models/file_transfer_state.dart';
import '../../models/incoming_file_offer.dart';
import '../../models/peer_device.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/transfer_history_card.dart';

/// Active peer session UI: connected devices, pending offers and transfers.
class ConnectionScreen extends StatelessWidget {
  const ConnectionScreen({
    super.key,
    required this.self,
    required this.peer,
    required this.pendingOffers,
    required this.transfers,
    required this.hasActiveTransfer,
    required this.onSendFile,
    required this.onDisconnect,
    required this.onAccept,
    required this.onReject,
    required this.onCancelTransfer,
    this.showHistory = true,
  });

  final PeerDevice self;
  final PeerDevice peer;
  final List<IncomingFileOffer> pendingOffers;
  final List<FileTransferState> transfers;
  final bool hasActiveTransfer;
  final VoidCallback onSendFile;
  final VoidCallback onDisconnect;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;
  final ValueChanged<String> onCancelTransfer;
  final bool showHistory;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTransfer = transfers.where((transfer) => transfer.isActive);
    final activeTransfers = activeTransfer.toList(growable: false);
    final label = activeTransfer.isEmpty
        ? 'ເຊື່ອມຕໍ່ແລ້ວ · ພ້ອມສົ່ງໄຟລ໌'
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
                OutlinedButton.icon(
                  onPressed: onDisconnect,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('ຕັດການເຊື່ອມຕໍ່'),
                ),
              ],
            ),
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
