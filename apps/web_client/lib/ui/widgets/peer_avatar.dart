import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';
import '../../models/peer_device.dart';
import '../../models/picked_file.dart';

/// ປຸ່ມອຸປະກອນປາຍທາງ + DragTarget ຮັບໄຟລ໌.
class PeerAvatar extends StatefulWidget {
  const PeerAvatar({
    super.key,
    required this.peer,
    this.isSelf = false,
    this.onTap,
    this.onFilesDropped,
    this.diameter = 92,
  });

  final PeerDevice peer;
  final bool isSelf;
  final VoidCallback? onTap;
  final void Function(List<PickedFile> files)? onFilesDropped;
  final double diameter;

  @override
  State<PeerAvatar> createState() => _PeerAvatarState();
}

class _PeerAvatarState extends State<PeerAvatar> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget avatar = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: widget.diameter,
      height: widget.diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: widget.isSelf ? null : YonTheme.primaryGradient,
        color: widget.isSelf
            ? (isDark ? YonTheme.slateDarkCard : Colors.white)
            : null,
        border: widget.isSelf
            ? Border.all(color: YonTheme.yonOrange, width: 1.5)
            : Border.all(color: YonTheme.yonOrange.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: YonTheme.yonOrange.withValues(alpha: _hovering ? 0.45 : 0.22),
            blurRadius: _hovering ? 26 : 14,
            spreadRadius: _hovering ? 2 : 0,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          widget.peer.icon,
          size: widget.diameter * 0.42,
          color: widget.isSelf
              ? YonTheme.yonOrange
              : Colors.white,
        ),
      ),
    );

    if (!widget.isSelf && widget.onFilesDropped != null) {
      final baseAvatar = avatar;
      avatar = DragTarget<List<PickedFile>>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) => widget.onFilesDropped?.call(details.data),
        builder: (context, candidate, rejected) {
          final active = candidate.isNotEmpty;
          return AnimatedScale(
            scale: active ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: baseAvatar,
          );
        },
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovering = true),
      onTapUp: (_) => setState(() => _hovering = false),
      onTapCancel: () => setState(() => _hovering = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(height: 8),
          SizedBox(
            width: widget.diameter + 24,
            child: Text(
              widget.peer.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.isSelf)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'ຕົວທ່ານ',
                style: TextStyle(fontSize: 10, color: YonTheme.yonOrange),
              ),
            ),
        ],
      ),
    );
  }
}
