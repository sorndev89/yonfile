import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/peer_device.dart';
import '../../models/picked_file.dart';
import 'peer_avatar.dart';

class RadarPeers extends StatelessWidget {
  const RadarPeers({
    super.key,
    required this.self,
    required this.peers,
    required this.connectedPeerIds,
    required this.onTapPeer,
    required this.onLongPressPeer,
    required this.onDropFiles,
  });

  final PeerDevice self;
  final List<PeerDevice> peers;
  final Set<String> connectedPeerIds;
  final void Function(PeerDevice) onTapPeer;
  final void Function(PeerDevice) onLongPressPeer;
  final void Function(PeerDevice, List<PickedFile>) onDropFiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );
        final radius = math.max(
          48.0,
          (math.min(constraints.maxWidth, constraints.maxHeight) / 2) - 82,
        );

        final widgets = <Widget>[];
        widgets.add(
          Positioned(
            left: center.dx - 52,
            top: center.dy - 52,
            child: PeerAvatar(peer: self, isSelf: true, diameter: 88),
          ),
        );

        final count = peers.length;
        final rings = math.max(1, (count / 8).ceil());
        for (var i = 0; i < count; i++) {
          final ring = i ~/ 8;
          final ringStart = ring * 8;
          final ringCount = math.min(8, count - ringStart);
          final ringRadius = radius * ((ring + 1) / rings);
          final angle =
              -math.pi / 2 + ((i - ringStart) * 2 * math.pi / ringCount);
          final dx = center.dx + ringRadius * math.cos(angle) - 44;
          final dy = center.dy + ringRadius * math.sin(angle) - 44;
          final peer = peers[i];
          widgets.add(
            Positioned(
              left: dx,
              top: dy,
              child: GestureDetector(
                onLongPress: () => onLongPressPeer(peer),
                child: PeerAvatar(
                  peer: peer,
                  diameter: 76,
                  isConnected: connectedPeerIds.contains(peer.id),
                  onTap: () => onTapPeer(peer),
                  onFilesDropped: (files) => onDropFiles(peer, files),
                ),
              ),
            ),
          );
        }
        return Stack(children: widgets);
      },
    );
  }
}
