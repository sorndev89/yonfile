class LocalSignalingHost {
  int get port => 0;

  Future<List<String>> start({int port = 3001}) async =>
      throw UnsupportedError('Offline LAN host is available in native apps.');

  Future<void> stop() async {}
}
