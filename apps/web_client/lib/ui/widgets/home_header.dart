import 'package:flutter/material.dart';

import '../../core/theme/yon_theme.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.signalingConnected,
    required this.usingLocalSignaling,
    required this.activeTransferCount,
    required this.themeMode,
    required this.onOfflineSettings,
    required this.onTransferHistory,
    required this.onToggleTheme,
  });

  final bool signalingConnected;
  final bool usingLocalSignaling;
  final int activeTransferCount;
  final ThemeMode themeMode;
  final VoidCallback onOfflineSettings;
  final VoidCallback onTransferHistory;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 6),
      child: Row(
        children: [
          Image.asset(
            'assets/branding/yonfile-mark.png',
            width: 28,
            height: 28,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              children: [
                const TextSpan(text: 'Yon'),
                TextSpan(
                  text: 'File',
                  style: TextStyle(color: YonTheme.yonOrange),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: signalingConnected
                  ? YonTheme.emeraldGreen
                  : YonTheme.amberGold,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: usingLocalSignaling
                ? 'ໃຊ້ signaling server ອອນລາຍ'
                : 'ຕັ້ງຄ່າໃຊ້ງານ offline ໃນ LAN',
            onPressed: onOfflineSettings,
            icon: Icon(
              usingLocalSignaling
                  ? Icons.wifi_tethering_rounded
                  : Icons.wifi_tethering_off_rounded,
              color: usingLocalSignaling ? YonTheme.yonOrange : null,
            ),
          ),
          if (activeTransferCount > 0)
            _BadgeIconButton(
              icon: Icons.swap_vert_rounded,
              count: activeTransferCount,
              onTap: onTransferHistory,
            ),
          IconButton(
            tooltip: 'ແຈ້ງເຕືອນ',
            onPressed: onTransferHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'ປ່ຽນໂໝດສີ',
            onPressed: onToggleTheme,
            icon: Icon(
              themeMode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class DeviceNameHeader extends StatelessWidget {
  const DeviceNameHeader({
    super.key,
    required this.name,
    required this.icon,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: YonTheme.yonOrange),
            const SizedBox(width: 6),
            Text(
              'ຊື່ເຄື່ອງ: $name',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_rounded, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _BadgeIconButton extends StatelessWidget {
  const _BadgeIconButton({
    required this.icon,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(onPressed: onTap, icon: Icon(icon)),
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: YonTheme.yonOrange,
              shape: BoxShape.circle,
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
