import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';
import '../../models/file_transfer_state.dart';
import 'transfer_sheet.dart';

class TransferStatusPanel extends StatelessWidget {
  const TransferStatusPanel({
    super.key,
    required this.transfers,
    required this.onCancel,
  });

  final List<FileTransferState> transfers;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              const Icon(
                Icons.bar_chart_rounded,
                color: YonTheme.yonOrange,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'ສະຖານະການໂຍນໄຟລ໌',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (transfers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'ຍັງບໍ່ມີການໂຍນໄຟລ໌',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            )
          else
            TransferSheet(
              transfers: transfers,
              onCancel: onCancel,
              showHeader: false,
            ),
        ],
      ),
    );
  }
}
