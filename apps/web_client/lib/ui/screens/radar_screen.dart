import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/theme/yon_theme.dart';
import '../../models/peer_device.dart';
import '../../models/picked_file.dart';
import '../widgets/radar_canvas.dart';
import '../widgets/radar_peers.dart';

enum _PeerFilter { all, sameNetwork }

enum _RadarView { radar, list }

/// Device discovery screen. It owns the radar and desktop drag-and-drop UI.
class RadarScreen extends StatefulWidget {
  const RadarScreen({
    super.key,
    required this.self,
    required this.peers,
    required this.sameNetworkPeerIds,
    required this.externalIpPeerIds,
    required this.pinPeerIds,
    required this.connectedPeerIds,
    required this.signalingConnected,
    required this.onTapPeer,
    required this.onLongPressPeer,
    required this.onDroppedFiles,
    required this.onDropRejected,
  });

  final PeerDevice self;
  final List<PeerDevice> peers;

  /// IDs grouped by the signaling server's observed public IP. This is a
  /// network hint, not proof that devices share a private LAN.
  final Set<String> sameNetworkPeerIds;
  final Set<String> externalIpPeerIds;
  final Set<String> pinPeerIds;
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
  _PeerFilter _filter = _PeerFilter.all;
  _RadarView _view = _RadarView.radar;
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  List<PeerDevice> get _visiblePeers => widget.peers
      .where(
        (peer) =>
            _filter == _PeerFilter.all ||
            widget.sameNetworkPeerIds.contains(peer.id),
      )
      .toList(growable: false);

  void _zoomBy(double factor) {
    final current = _transform.value;
    final scale = current.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(0.65, 3.0);
    _transform.value = Matrix4.identity()..scaleByDouble(next, next, 1, 1);
  }

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
              Positioned(
                left: 12,
                right: 12,
                top: 12,
                child: _buildControls(context),
              ),
              Positioned.fill(
                top: 62,
                child: _view == _RadarView.radar
                    ? InteractiveViewer(
                        transformationController: _transform,
                        minScale: 0.65,
                        maxScale: 3,
                        boundaryMargin: const EdgeInsets.all(240),
                        trackpadScrollCausesScale: true,
                        child: RadarPeers(
                          self: widget.self,
                          peers: _visiblePeers,
                          connectedPeerIds: widget.connectedPeerIds,
                          onTapPeer: widget.onTapPeer,
                          onLongPressPeer: widget.onLongPressPeer,
                          onDropFiles: (peer, files) =>
                              widget.onDroppedFiles(files, peer),
                        ),
                      )
                    : _buildPeerList(context),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Text(
                    widget.peers.isEmpty
                        ? 'ກຳລັງຊອກຫາ YonFile ໃນ LAN...'
                        : _visiblePeers.isEmpty
                        ? 'ບໍ່ພົບອຸປະກອນໃນໝວດນີ້'
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

  Widget _buildControls(BuildContext context) {
    final localCount = widget.peers
        .where((peer) => widget.sameNetworkPeerIds.contains(peer.id))
        .length;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Row(
          children: [
            SegmentedButton<_PeerFilter>(
              segments: [
                ButtonSegment(
                  value: _PeerFilter.all,
                  label: Text('ທັງໝົດ ${widget.peers.length}'),
                  icon: const Icon(Icons.devices_rounded),
                ),
                ButtonSegment(
                  value: _PeerFilter.sameNetwork,
                  label: Text('LAN $localCount'),
                  tooltip: 'ພົບຜ່ານ mDNS ຫຼື offline host ໃນ LAN',
                  icon: const Icon(Icons.wifi_rounded),
                ),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              style: _compactControlStyle,
              onSelectionChanged: (selected) =>
                  setState(() => _filter = selected.first),
            ),
            const SizedBox(width: 8),
            SegmentedButton<_RadarView>(
              segments: const [
                ButtonSegment(
                  value: _RadarView.radar,
                  icon: Icon(Icons.radar_rounded),
                  tooltip: 'Radar',
                ),
                ButtonSegment(
                  value: _RadarView.list,
                  icon: Icon(Icons.view_list_rounded),
                  tooltip: 'ລາຍຊື່',
                ),
              ],
              selected: {_view},
              showSelectedIcon: false,
              style: _compactControlStyle,
              onSelectionChanged: (selected) =>
                  setState(() => _view = selected.first),
            ),
            if (_view == _RadarView.radar) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'ຫຍໍ້',
                onPressed: () => _zoomBy(0.8),
                icon: const Icon(Icons.remove_rounded),
                style: _compactZoomStyle,
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'ຂະຫຍາຍ',
                onPressed: () => _zoomBy(1.25),
                icon: const Icon(Icons.add_rounded),
                style: _compactZoomStyle,
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'ກັບສູ່ຂະໜາດເຕັມ',
                onPressed: () => _transform.value = Matrix4.identity(),
                icon: const Icon(Icons.center_focus_strong_rounded),
                style: _compactZoomStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }

  ButtonStyle get _compactControlStyle => ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    iconSize: const WidgetStatePropertyAll(16),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  ButtonStyle get _compactZoomStyle => ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
    iconSize: const WidgetStatePropertyAll(18),
    minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _buildPeerList(BuildContext context) {
    final peers = _visiblePeers;
    if (peers.isEmpty) {
      return Center(child: Text('ບໍ່ພົບອຸປະກອນໃນຕົວກອງນີ້'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 58),
      itemCount: peers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final peer = peers[index];
        final connected = widget.connectedPeerIds.contains(peer.id);
        final sameNetwork = widget.sameNetworkPeerIds.contains(peer.id);
        final samePublicIp = widget.externalIpPeerIds.contains(peer.id);
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: YonTheme.yonOrange.withValues(alpha: 0.14),
              child: Icon(peer.icon, color: YonTheme.yonOrange),
            ),
            title: Text(
              peer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${peer.operatingSystemLabel} · ${_sourceLabel(peer, sameNetwork, samePublicIp)} · ${connected ? 'ເຊື່ອມຕໍ່ແລ້ວ' : 'ພ້ອມເຊື່ອມຕໍ່'}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => widget.onTapPeer(peer),
          ),
        );
      },
    );
  }

  String _sourceLabel(PeerDevice peer, bool sameNetwork, bool samePublicIp) {
    final inPin = widget.pinPeerIds.contains(peer.id);
    if (sameNetwork && inPin) return 'LAN · PIN';
    if (sameNetwork) return 'ພົບໃນ LAN';
    if (samePublicIp && inPin) return 'IP ອອກເນັດຄືກັນ · PIN';
    if (samePublicIp) return 'IP ອອກເນັດຄືກັນ';
    return 'ພົບຜ່ານ PIN';
  }
}
