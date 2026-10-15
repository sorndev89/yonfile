import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/yon_theme.dart';

/* ------------------------------ QR Scanner ------------------------------- */

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      final digits = RegExp(r'\d{6}').firstMatch(value)?.group(0);
      if (digits != null) {
        _handled = true;
        Navigator.of(context).pop(digits);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ສະແກນ QR Code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              _error ??= error.errorDetails?.message ?? error.errorCode.name;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.no_photography_rounded,
                        size: 48,
                        color: YonTheme.roseRed,
                      ),
                      const SizedBox(height: 12),
                      const Text('ເປີດກ້ອງບໍ່ໄດ້'),
                      const SizedBox(height: 6),
                      Text(
                        _error ?? 'ກະລຸນາອະນຸຍາດການໃຊ້ກ້ອງ ແລະໃຊ້ HTTPS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _controller.start(),
                        child: const Text('ລອງໃໝ່'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final frameSize = math.min(
                    300.0,
                    math.min(
                      constraints.maxWidth - 48,
                      constraints.maxHeight * 0.42,
                    ),
                  );
                  final frameRect = Rect.fromCenter(
                    center: Offset(
                      constraints.maxWidth / 2,
                      constraints.maxHeight * 0.46,
                    ),
                    width: frameSize,
                    height: frameSize,
                  );
                  return Stack(
                    children: [
                      CustomPaint(
                        size: Size.infinite,
                        painter: _ScannerDimPainter(frameRect),
                      ),
                      Positioned.fromRect(
                        rect: frameRect,
                        child: Stack(
                          children: [
                            const Positioned(
                              left: -1,
                              top: -1,
                              child: _ScannerCorner(),
                            ),
                            const Positioned(
                              right: -1,
                              top: -1,
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: _ScannerCorner(),
                              ),
                            ),
                            const Positioned(
                              right: -1,
                              bottom: -1,
                              child: RotatedBox(
                                quarterTurns: 2,
                                child: _ScannerCorner(),
                              ),
                            ),
                            const Positioned(
                              left: -1,
                              bottom: -1,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: _ScannerCorner(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 32,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: YonTheme.yonOrange,
                                  size: 19,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'ຈັດ QR Code ໃຫ້ຢູ່ໃນກອບ',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerDimPainter extends CustomPainter {
  const _ScannerDimPainter(this.frameRect);

  final Rect frameRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(24)));
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.52),
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerDimPainter oldDelegate) =>
      oldDelegate.frameRect != frameRect;
}

class _ScannerCorner extends StatelessWidget {
  const _ScannerCorner();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: CustomPaint(painter: _ScannerCornerPainter()),
    );
  }
}

class _ScannerCornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(2, size.height - 4)
      ..lineTo(2, 10)
      ..quadraticBezierTo(2, 2, 10, 2)
      ..lineTo(size.width - 4, 2);
    final glow = Paint()
      ..color = YonTheme.yonOrange.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final stroke = Paint()
      ..color = YonTheme.yonOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, glow);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ScannerCornerPainter oldDelegate) => false;
}
