import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';
import '../../models/file_transfer_state.dart';

/// Modal ສະແດງຄວາມຄືບໜ້າການໂຍນໄຟລ໌.
class TransferSheet extends StatelessWidget {
  const TransferSheet({
    super.key,
    required this.transfers,
    required this.onCancel,
    this.onClearCompleted,
    this.showHeader = true,
  });

  final List<FileTransferState> transfers;
  final ValueChanged<String> onCancel;
  final VoidCallback? onClearCompleted;
  final bool showHeader;

  /// ສະແດງໃນ Modal Bottom Sheet.
  static Future<void> show(
    BuildContext context, {
    required List<FileTransferState> transfers,
    required ValueListenable<int> revision,
    required ValueChanged<String> onCancel,
    VoidCallback? onClearCompleted,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: revision,
        builder: (_, _, _) => TransferSheet(
          transfers: transfers,
          onCancel: onCancel,
          onClearCompleted: onClearCompleted,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      decoration: BoxDecoration(
        color: isDark ? YonTheme.slateDarkBg : YonTheme.lightBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (showHeader)
              Row(
                children: [
                  const Icon(
                    Icons.swap_vert_rounded,
                    color: YonTheme.yonOrange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'ການໂຍນໄຟລ໌',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (onClearCompleted != null)
                    TextButton(
                      onPressed: onClearCompleted,
                      child: const Text('ລ້າງທີ່ສຳເລັດ'),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            if (transfers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    'ຍັງບໍ່ມີການໂຍນໄຟລ໌',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: transfers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _TransferTile(
                    transfer: transfers[index],
                    onCancel: () => onCancel(transfers[index].id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.transfer, required this.onCancel});

  final FileTransferState transfer;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSend = transfer.direction == TransferDirection.send;
    final status = _statusMeta(transfer.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? YonTheme.slateDarkCard.withValues(alpha: 0.8)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSend ? Icons.upload_rounded : Icons.download_rounded,
                color: status.color,
                size: 20,
              ),
              const SizedBox(width: 8),
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
                    Text(
                      '${isSend ? 'ຫາ' : 'ຈາກ'} ${transfer.peerName}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              if (transfer.isActive)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onCancel,
                  icon: const Icon(
                    Icons.close_rounded,
                    color: YonTheme.roseRed,
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: transfer.status == TransferStatus.completed
                  ? 1
                  : transfer.progress,
              minHeight: 8,
              backgroundColor: isDark
                  ? Colors.white12
                  : Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(status.color),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final statusText = Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status.color,
                ),
              );
              final percentText = Text(
                '${transfer.percent}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              );
              final sizeText = Text(
                '${transfer.readableTransferred} / ${transfer.readableSize}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : Colors.black45,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              );
              final speedText = Text(
                '⚡ ${transfer.readableSpeed}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: YonTheme.yonOrange,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              );

              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: statusText),
                        const SizedBox(width: 12),
                        percentText,
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: sizeText),
                        if (transfer.status == TransferStatus.transferring) ...[
                          const SizedBox(width: 8),
                          Flexible(child: speedText),
                        ],
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 2, child: statusText),
                  const SizedBox(width: 10),
                  percentText,
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: sizeText),
                  if (transfer.status == TransferStatus.transferring) ...[
                    const SizedBox(width: 10),
                    Flexible(flex: 2, child: speedText),
                  ],
                ],
              );
            },
          ),
          if (transfer.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                transfer.error!,
                style: const TextStyle(fontSize: 11, color: YonTheme.roseRed),
              ),
            ),
        ],
      ),
    );
  }

  _StatusMeta _statusMeta(TransferStatus status) {
    switch (status) {
      case TransferStatus.offering:
      case TransferStatus.awaitingAccept:
        return const _StatusMeta('ລໍຖ້າການຍອມຮັບ', YonTheme.amberGold);
      case TransferStatus.transferring:
        return const _StatusMeta('ກຳລັງໂຍນ...', YonTheme.yonOrange);
      case TransferStatus.verifying:
        return const _StatusMeta('ກຳລັງກວດສອບ SHA-256', YonTheme.amberGold);
      case TransferStatus.completed:
        return const _StatusMeta('ສຳເລັດ', YonTheme.emeraldGreen);
      case TransferStatus.failed:
        return const _StatusMeta('ລົ້ມເຫຼວ', YonTheme.roseRed);
      case TransferStatus.cancelled:
        return const _StatusMeta('ຍົກເລີກແລ້ວ', YonTheme.roseRed);
      case TransferStatus.idle:
        return const _StatusMeta('ຣໍຖ້າ', YonTheme.amberGold);
    }
  }
}

class _StatusMeta {
  const _StatusMeta(this.label, this.color);
  final String label;
  final Color color;
}
