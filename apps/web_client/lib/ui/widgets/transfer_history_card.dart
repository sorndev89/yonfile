import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';
import '../../models/file_transfer_state.dart';

/// Compact list of recent finished transfers for the connected-device view.
class TransferHistoryCard extends StatelessWidget {
  const TransferHistoryCard({
    super.key,
    required this.transfers,
    this.maxItems = 6,
  });

  final List<FileTransferState> transfers;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final history = transfers
        .where(
          (transfer) =>
              transfer.status == TransferStatus.completed ||
              transfer.status == TransferStatus.failed ||
              transfer.status == TransferStatus.cancelled,
        )
        .take(maxItems)
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? YonTheme.slateDarkCard.withValues(alpha: 0.8)
            : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: YonTheme.yonOrange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: YonTheme.yonOrange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ປະຫວັດການໂອນໄຟລ໌',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (history.isNotEmpty)
                Text(
                  '${history.length}',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'ຍັງບໍ່ມີປະຫວັດການໂອນ',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 12,
                  ),
                ),
              ),
            )
          else
            for (var index = 0; index < history.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 14,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              _HistoryRow(transfer: history[index]),
            ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.transfer});

  final FileTransferState transfer;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = switch (transfer.status) {
      TransferStatus.completed => YonTheme.emeraldGreen,
      TransferStatus.failed => YonTheme.roseRed,
      TransferStatus.cancelled => isDark ? Colors.white54 : Colors.black45,
      _ => YonTheme.yonOrange,
    };
    final icon = switch (transfer.status) {
      TransferStatus.completed => Icons.check_circle_rounded,
      TransferStatus.failed => Icons.error_rounded,
      TransferStatus.cancelled => Icons.cancel_rounded,
      _ => Icons.help_rounded,
    };
    final status = switch (transfer.status) {
      TransferStatus.completed => 'ສຳເລັດ',
      TransferStatus.failed => 'ລົ້ມເຫຼວ',
      TransferStatus.cancelled => 'ຍົກເລີກ',
      _ => '',
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transfer.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${transfer.direction == TransferDirection.send ? 'ຫາ' : 'ຈາກ'} ${transfer.peerName} · ${transfer.readableSize}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          status,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
