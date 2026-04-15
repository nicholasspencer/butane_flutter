import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

/// Thin seam around platform-specific mDNS service advertisement.
///
/// The `nsd` package has no Linux backend; on Linux we shell out to
/// `avahi-publish-service` (ships in `avahi-utils`). Everywhere else we
/// use `nsd` unchanged.
abstract class MdnsAdvertiser {
  factory MdnsAdvertiser() =>
      Platform.isLinux ? _AvahiCliAdvertiser() : _NsdAdvertiser();

  Future<void> register({
    required String name,
    required String type,
    required int port,
    required Map<String, String> txt,
  });

  Future<void> unregister();
}

class _NsdAdvertiser implements MdnsAdvertiser {
  nsd.Registration? _reg;

  @override
  Future<void> register({
    required String name,
    required String type,
    required int port,
    required Map<String, String> txt,
  }) async {
    _reg = await nsd.register(
      nsd.Service(
        name: name,
        type: type,
        port: port,
        txt: {
          for (final e in txt.entries)
            e.key: Uint8List.fromList(utf8.encode(e.value)),
        },
      ),
    );
  }

  @override
  Future<void> unregister() async {
    final reg = _reg;
    if (reg != null) {
      await nsd.unregister(reg);
      _reg = null;
    }
  }
}

class _AvahiCliAdvertiser implements MdnsAdvertiser {
  Process? _proc;

  @override
  Future<void> register({
    required String name,
    required String type,
    required int port,
    required Map<String, String> txt,
  }) async {
    final txtArgs = [for (final e in txt.entries) '${e.key}=${e.value}'];
    try {
      _proc = await Process.start(
        'avahi-publish-service',
        [name, type, port.toString(), ...txtArgs],
        mode: ProcessStartMode.detachedWithStdio,
      );
    } on ProcessException catch (e) {
      throw StateError(
        'avahi-publish-service not found on PATH. '
        'Install it with: sudo apt install avahi-utils. ($e)',
      );
    }
  }

  @override
  Future<void> unregister() async {
    _proc?.kill();
    _proc = null;
  }
}
