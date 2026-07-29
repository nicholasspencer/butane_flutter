/// Shared launch-readiness scraping for follower launchers.
///
/// A launched app-under-test publishes its VM-service endpoint on stdout:
/// the `GRID_VM_URI=<ws://…/ws>` sentinel (primary — printed AFTER the
/// exploration host has registered, so the first drive call can never race
/// extension registration) with the VM's own service banner as a fallback.
/// Both [LocalDartFollowerLauncher] and [ButaneFollowerLauncher] scrape
/// through this one implementation.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Completes with the launched [process]'s ws:// VM-service URI: the
/// `GRID_VM_URI=` sentinel (primary) or the VM's
/// `The Dart VM service is listening on <http…>` banner (fallback, converted
/// to the ws + `/ws` form after [bannerGrace] — the sentinel follows
/// registration, so the banner alone gets a grace window to be superseded).
/// Keeps draining both stdio streams after completion so the child can never
/// block on a full pipe. [onLine] observes every line (log forwarding).
Future<String> scrapeVmServiceWsUri(
  Process process, {
  Duration bannerGrace = const Duration(seconds: 10),
  void Function(String)? onLine,
}) {
  final completer = Completer<String>();
  String? bannerUri;
  Timer? bannerFallback;

  void inspect(String line) {
    onLine?.call(line);
    if (completer.isCompleted) return;
    final trimmed = line.trim();
    final sentinel = RegExp(r'GRID_VM_URI=(\S+)').firstMatch(trimmed);
    if (sentinel != null) {
      bannerFallback?.cancel();
      completer.complete(sentinel.group(1));
      return;
    }
    final banner = RegExp(
      r'The Dart VM service is listening on (\S+)',
    ).firstMatch(trimmed);
    if (banner != null && bannerUri == null) {
      bannerUri = vmServiceHttpToWs(banner.group(1)!);
      bannerFallback = Timer(bannerGrace, () {
        if (!completer.isCompleted) completer.complete(bannerUri);
      });
    }
  }

  void drain(Stream<List<int>> stream) {
    stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(inspect, onError: (Object _) {}, cancelOnError: false);
  }

  drain(process.stdout);
  drain(process.stderr);
  return completer.future;
}

/// `http://127.0.0.1:PORT/[token/]` → `ws://127.0.0.1:PORT/[token/]ws`
/// (the attach-test URI form).
String vmServiceHttpToWs(String httpUri) {
  final uri = Uri.parse(httpUri);
  final path = uri.path.endsWith('/') ? '${uri.path}ws' : '${uri.path}/ws';
  return uri
      .replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws', path: path)
      .toString();
}

/// Returns flutter's mac-side usbmux-forwarded VM-service URI from [output].
///
/// App-owned `GRID_VM_URI` sentinels are deliberately ignored because on iOS
/// they name the device-side, loopback-bound service and carry a different
/// authentication code.
String? flutterForwardedVmServiceWsUri(String output) {
  final match = RegExp(
    r'(?:A Dart VM Service on|The Flutter DevTools debugger and profiler on)'
    r'[^\n]*? is available at: (https?://127\.0\.0\.1:\d+/\S*)',
  ).firstMatch(output);
  final httpUri = match?.group(1);
  return httpUri == null ? null : vmServiceHttpToWs(httpUri);
}
