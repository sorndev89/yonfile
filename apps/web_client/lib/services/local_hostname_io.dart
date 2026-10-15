import 'dart:io';

Future<String?> getLocalHostname() async {
  final hostname = Platform.localHostname.trim();
  return hostname.isEmpty ? null : hostname;
}
