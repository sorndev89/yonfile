import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/yon_theme.dart';
import '../../services/app_log_service.dart';

/// Modal ສະແດງບັນທຶກ Log ແລະ ວິເຄາະບັນຫາການເຊື່ອມຕໍ່/ໂອນໄຟລ໌
class LogViewerDialog extends StatefulWidget {
  const LogViewerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const LogViewerDialog(),
    );
  }

  @override
  State<LogViewerDialog> createState() => _LogViewerDialogState();
}

class _LogViewerDialogState extends State<LogViewerDialog> {
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? YonTheme.slateDarkBg : YonTheme.lightBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 680,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: YonTheme.yonOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.terminal_rounded,
                    color: YonTheme.yonOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ບັນທຶກ Log & ກວດສອບບັນຫາ',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'ໃຊ້ສຳລັບວິເຄາະເມື່ອການເຊື່ອມຕໍ່ ຫຼື ໂອນໄຟລ໌ບໍ່ສຳເລັດ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'ປິດ',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // System Environment Diagnostics Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? YonTheme.slateDarkCard.withValues(alpha: 0.6)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _DiagnosticItem(
                    label: 'Platform',
                    value: kIsWeb ? 'Web Browser' : defaultTargetPlatform.name,
                    icon: Icons.language_rounded,
                  ),
                  if (kIsWeb)
                    _DiagnosticItem(
                      label: 'File API',
                      value: 'Stream / Blob',
                      icon: Icons.folder_zip_rounded,
                    ),
                  _DiagnosticItem(
                    label: 'Logs',
                    value: '${AppLogService.instance.logs.length} ລາຍການ',
                    icon: Icons.receipt_long_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Filter Chips & Action Buttons
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('all', 'ທັງໝົດ'),
                        const SizedBox(width: 6),
                        _buildFilterChip('error', 'ສະເພາະ Error'),
                        const SizedBox(width: 6),
                        _buildFilterChip('WebRTC', 'WebRTC'),
                        const SizedBox(width: 6),
                        _buildFilterChip('Transfer', 'Transfer'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'ສຳເນົາ Log ທັງໝົດ',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    final text = AppLogService.instance.exportText();
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ສຳເນົາ Log ທັງໝົດລົງ Clipboard ແລ້ວ'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'ລ້າງ Log',
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: () {
                    setState(() => AppLogService.instance.clear());
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Log entries list
            Expanded(
              child: ListenableBuilder(
                listenable: AppLogService.instance,
                builder: (context, _) {
                  final allLogs = AppLogService.instance.logs;
                  final filtered = allLogs.where((log) {
                    if (_selectedFilter == 'all') return true;
                    if (_selectedFilter == 'error') {
                      return log.level == LogLevel.error;
                    }
                    return log.tag.toLowerCase() ==
                        _selectedFilter.toLowerCase();
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 48,
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _selectedFilter == 'error'
                                ? 'ບໍ່ມີບັນທຶກ Error'
                                : 'ຍັງບໍ່ມີບັນທຶກ Log',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0B1120)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(
                        height: 8,
                        thickness: 0.5,
                        color: Colors.white10,
                      ),
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        return _LogEntryTile(entry: entry, isDark: isDark);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final selected = _selectedFilter == key;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : null,
      ),
      selectedColor: YonTheme.yonOrange,
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }
}

class _DiagnosticItem extends StatelessWidget {
  const _DiagnosticItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: YonTheme.yonOrange),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({required this.entry, required this.isDark});

  final LogEntry entry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      LogLevel.error => YonTheme.roseRed,
      LogLevel.warning => YonTheme.amberGold,
      LogLevel.success => YonTheme.emeraldGreen,
      LogLevel.info => isDark ? Colors.white70 : const Color(0xFF334155),
    };

    final icon = switch (entry.level) {
      LogLevel.error => Icons.error_rounded,
      LogLevel.warning => Icons.warning_rounded,
      LogLevel.success => Icons.check_circle_rounded,
      LogLevel.info => Icons.info_outline_rounded,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            entry.timeFormatted,
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isDark ? Colors.white38 : Colors.black38,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              entry.tag,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                text: entry.message,
                style: TextStyle(fontSize: 12, color: color),
                children: [
                  if (entry.details != null)
                    TextSpan(
                      text: '\n${entry.details}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

