import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/yon_theme.dart';
import '../../models/peer_device.dart';
import '../../models/picked_file.dart';
import '../widgets/radar_canvas.dart';
import '../widgets/radar_peers.dart';

/// Device discovery screen. It owns the radar and desktop drag-and-drop UI.
class RadarScreen extends StatefulWidget {
  const RadarScreen({
    super.key,
    required this.self,
    required this.peers,
    required this.connectedPeerIds,
    required this.signalingConnected,
    required this.onTapPeer,
    required this.onLongPressPeer,
    required this.onDroppedFiles,
    required this.onDropRejected,
  });

  final PeerDevice self;
  final List<PeerDevice> peers;
  final Set<String> connectedPeerIds;
  final bool signalingConnected;
  final ValueChanged<PeerDevice> onTapPeer;
  final ValueChanged<PeerDevice> onLongPressPeer;
  final Future<void> Function(List<PickedFile> files, PeerDevice? target)
  onDroppedFiles;
  final ValueChanged<String> onDropRejected;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  bool _draggingOver = false;

  String _guessMime(String name) {
    switch (name.split('.').last.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    setState(() => _draggingOver = false);
    final picked = <PickedFile>[];
    var totalBytes = 0;
    for (final item in details.files) {
      final knownSize = await item.length();
      if (totalBytes + knownSize > AppConfig.maxFileSizeBytes) {
        widget.onDropRejected('ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ 512 MB');
        return;
      }
      final bytes = await item.readAsBytes();
      if (totalBytes + bytes.length > AppConfig.maxFileSizeBytes) {
        widget.onDropRejected('ຂະໜາດລວມຂອງໄຟລ໌ເກີນຂີດຈຳກັດ 512 MB');
        return;
      }
      totalBytes += bytes.length;
      picked.add(
        PickedFile(
          name: item.name,
          size: bytes.length,
          bytes: bytes,
          mimeType: _guessMime(item.name),
        ),
      );
    }
    if (picked.isNotEmpty) await widget.onDroppedFiles(picked, null);
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingOver = true),
      onDragExited: (_) => setState(() => _draggingOver = false),
      onDragDone: _handleDrop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: _draggingOver ? YonTheme.yonOrange : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned.fill(
                child: RadarCanvas(active: widget.signalingConnected),
              ),
              Positioned.fill(
                child: RadarPeers(
                  self: widget.self,
                  peers: widget.peers,
                  connectedPeerIds: widget.connectedPeerIds,
                  onTapPeer: widget.onTapPeer,
                  onLongPressPeer: widget.onLongPressPeer,
                  onDropFiles: (peer, files) =>
                      widget.onDroppedFiles(files, peer),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Text(
                    widget.peers.isEmpty
                        ? 'ກຳລັງຊອກຫາອຸປະກອນ...'
                        : 'ແຕະໃສ່ອຸປະກອນເພື່ອເລືອກໄຟລ໌ · ລາກໄຟລ໌ມາວາງ',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.black45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
