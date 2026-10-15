import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/yon_theme.dart';

/// ກ່ອງລະຫັດຫ້ອງ PIN 6 ຕົວເລກ & QR Code ສຳລັບໂຍນຂ້າມເຄືອຂ່າຍ.
class PinRoomCard extends StatefulWidget {
  const PinRoomCard({
    super.key,
    required this.ownPin,
    required this.joinedPin,
    required this.onJoinPin,
    required this.onLeavePin,
    required this.onScan,
  });

  final String ownPin;
  final String? joinedPin;
  final ValueChanged<String> onJoinPin;
  final VoidCallback onLeavePin;
  final VoidCallback onScan;

  @override
  State<PinRoomCard> createState() => _PinRoomCardState();
}

class _PinRoomCardState extends State<PinRoomCard> {
  final _controller = TextEditingController();
  bool _showQr = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _grouped {
    final pin = widget.ownPin;
    if (pin.length == 6) return '${pin.substring(0, 3)} - ${pin.substring(3)}';
    return pin;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final joined = widget.joinedPin != null;

    return Container(
      padding: const EdgeInsets.all(18),
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
              const Icon(Icons.public_rounded, color: YonTheme.yonOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                'ໂຍນຂ້າມເຄືອຂ່າຍ (PIN)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'ລະຫັດຫ້ອງຂອງທ່ານ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: YonTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _grouped,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 3,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'ສຳເນົາ',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: widget.ownPin));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ສຳເນົາລະຫັດແລ້ວ')),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _showQr = !_showQr),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(_showQr ? 'ປິດ QR' : 'ສະແດງ QR Code'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('ສະແກນ'),
                ),
              ),
            ],
          ),
          if (_showQr) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: 'yonfile:${widget.ownPin}',
                  version: QrVersions.auto,
                  size: 160,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: YonTheme.yonOrange,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
          ],
          const Divider(height: 32),
          Text(
            'ຫຼື ໃສ່ລະຫັດເຄື່ອງອື່ນ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    hintText: 'ເຊັ່ນ 123456',
                    counterText: '',
                  ),
                  onSubmitted: (value) => _join(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _join,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                child: const Text('ເຊື່ອມຕໍ່'),
              ),
            ],
          ),
          if (joined) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: YonTheme.emeraldGreen, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ຢູ່ໃນຫ້ອງ ${widget.joinedPin}',
                    style: const TextStyle(
                      color: YonTheme.emeraldGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: widget.onLeavePin,
                  child: const Text(
                    'ອອກ',
                    style: TextStyle(color: YonTheme.roseRed),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _join() {
    final pin = _controller.text.trim();
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ກະລຸນາໃສ່ລະຫັດ 6 ຕົວເລກ')),
      );
      return;
    }
    widget.onJoinPin(pin);
  }
}
