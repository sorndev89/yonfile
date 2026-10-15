import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';

/// ວົງເຣດາສີສົ້ມແບບ CustomPaint Animation.
class RadarCanvas extends StatefulWidget {
  const RadarCanvas({super.key, this.active = true});

  final bool active;

  @override
  State<RadarCanvas> createState() => _RadarCanvasState();
}

class _RadarCanvasState extends State<RadarCanvas>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant RadarCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop(canceled: false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _RadarPainter(
        sweep: _controller,
        isDark: isDark,
        active: widget.active,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.sweep,
    required this.isDark,
    required this.active,
  }) : super(repaint: sweep) {
    final baseColor = YonTheme.yonOrange;
    _ringPaint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = baseColor.withValues(alpha: isDark ? 0.28 : 0.22);
    _crossPaint
      ..strokeWidth = 1
      ..color = baseColor.withValues(alpha: isDark ? 0.16 : 0.12);
    _sweepPaint.color = baseColor.withValues(alpha: isDark ? 0.16 : 0.12);
    _tipPaint
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = baseColor.withValues(alpha: 0.9);
    _centerPaint.color = baseColor.withValues(alpha: 0.9);
  }

  final Animation<double> sweep;
  final bool isDark;
  final bool active;
  final Paint _backgroundPaint = Paint();
  final Paint _ringPaint = Paint();
  final Paint _crossPaint = Paint();
  final Paint _sweepPaint = Paint();
  final Paint _tipPaint = Paint();
  final Paint _centerPaint = Paint();
  Shader? _backgroundShader;
  Size? _backgroundSize;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final baseColor = YonTheme.yonOrange;

    // ພື້ນຫຼັງ radial ອ່ອນໆ
    if (_backgroundShader == null || _backgroundSize != size) {
      _backgroundSize = size;
      _backgroundShader = RadialGradient(
        colors: [
          baseColor.withValues(alpha: isDark ? 0.10 : 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    }
    _backgroundPaint.shader = _backgroundShader;
    canvas.drawCircle(center, radius, _backgroundPaint);

    // ວົງຊ້ອນກັນ 3 ຊັ້ນ
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, _ringPaint);
    }

    // ເສັ້ນໄຂວ່
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      _crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      _crossPaint,
    );

    // ລຳແສງກວາດ (Restore classic radar sweep)
    if (active) {
      final sweepAngle = sweep.value * 2 * math.pi;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        sweepAngle - math.pi / 3,
        math.pi / 3,
        true,
        _sweepPaint,
      );

      final tipX = center.dx + radius * math.cos(sweepAngle);
      final tipY = center.dy + radius * math.sin(sweepAngle);
      canvas.drawLine(center, Offset(tipX, tipY), _tipPaint);
    }

    // ຈຸດໃຈກາງ
    canvas.drawCircle(
      center,
      3.5,
      _centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.isDark != isDark ||
      oldDelegate.active != active;
}
