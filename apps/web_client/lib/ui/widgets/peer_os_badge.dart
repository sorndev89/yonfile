import 'package:flutter/material.dart';

import '../../models/peer_device.dart';

class PeerOsBadge extends StatelessWidget {
  const PeerOsBadge({super.key, required this.peer, this.compact = false});

  final PeerDevice peer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white60
        : Colors.black54;
    return Tooltip(
      message: peer.operatingSystemLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(peer.operatingSystemIcon, size: compact ? 11 : 14, color: color),
          const SizedBox(width: 4),
          Text(
            peer.operatingSystemLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: compact ? 9 : 11, color: color),
          ),
        ],
      ),
    );
  }
}
