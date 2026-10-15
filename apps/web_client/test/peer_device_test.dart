import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yonfile_client/models/peer_device.dart';

void main() {
  test('peer metadata exposes platform-specific labels and icons', () {
    final android = PeerDevice.fromJson({
      'id': 'android-1',
      'name': 'Android',
      'deviceType': 'mobile',
      'operatingSystem': 'android',
      'scope': 'lan',
    });
    final mac = PeerDevice.fromJson({
      'id': 'mac-1',
      'name': 'Mac',
      'deviceType': 'desktop',
      'operatingSystem': 'macos',
      'scope': 'pin',
    });

    expect(android.operatingSystemLabel, 'Android');
    expect(android.operatingSystemIcon, Icons.android_rounded);
    expect(mac.operatingSystemLabel, 'macOS');
    expect(mac.operatingSystemIcon, Icons.laptop_mac_rounded);
  });

  test('legacy peers without OS metadata get a readable fallback', () {
    final peer = PeerDevice.fromJson({
      'id': 'legacy',
      'name': 'Legacy device',
      'deviceType': 'desktop',
      'scope': 'lan',
    });

    expect(peer.operatingSystem, PeerOperatingSystem.unknown);
    expect(peer.operatingSystemLabel, 'OS ບໍ່ລະບຸ');
  });

  test('same-name peers stay visible and get distinguishable labels', () {
    final peers = PeerDevice.disambiguateNames([
      const PeerDevice(
        id: 'abc123-first',
        name: 'Redmi Note',
        deviceType: PeerDeviceType.mobile,
        operatingSystem: PeerOperatingSystem.android,
        scope: PeerScope.pin,
      ),
      const PeerDevice(
        id: 'def456-second',
        name: 'redmi note',
        deviceType: PeerDeviceType.mobile,
        operatingSystem: PeerOperatingSystem.android,
        scope: PeerScope.pin,
      ),
    ]);

    expect(peers, hasLength(2));
    expect(peers[0].name, 'Redmi Note · Android #abc123');
    expect(peers[1].name, 'redmi note · Android #def456');
  });
}
