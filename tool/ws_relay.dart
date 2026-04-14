#!/usr/bin/env dart
// ignore_for_file: avoid_print
/// Simple WebSocket relay server.
///
/// Accepts exactly two connections: one from the harness app (role "harness")
/// and one from the coordinator (role "coordinator"). All messages from one
/// are forwarded to the other.
///
/// Usage:
///   dart tool/ws_relay.dart [--port 19101]
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  var port = 19101;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port' && i + 1 < args.length) {
      port = int.parse(args[i + 1]);
      i++;
    }
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('WS Relay listening on 0.0.0.0:$port');

  WebSocket? harness;
  WebSocket? coordinator;
  StreamSubscription<dynamic>? harnessSub;
  StreamSubscription<dynamic>? coordinatorSub;

  void cleanup() {
    harness?.close();
    coordinator?.close();
    harnessSub?.cancel();
    coordinatorSub?.cancel();
    server.close();
  }

  ProcessSignal.sigint.watch().listen((_) {
    print('\nRelay shutting down...');
    cleanup();
    exit(0);
  });

  await for (final request in server) {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..write('WebSocket connections only')
        ..close();
      continue;
    }

    final ws = await WebSocketTransformer.upgrade(request);
    final path = request.uri.path;
    final remoteAddr =
        '${request.connectionInfo?.remoteAddress.address}:${request.connectionInfo?.remotePort}';

    if (path == '/harness' || (harness == null && coordinator != null)) {
      // This is the harness (iPad) connection.
      if (harness != null) {
        print('Relay: Replacing stale harness connection');
        harnessSub?.cancel();
        harness!.close();
      }
      harness = ws;
      print('Relay: Harness connected from $remoteAddr');

      harnessSub = ws.listen(
        (data) {
          // Forward harness → coordinator.
          if (coordinator != null) {
            coordinator!.add(data);
          }
        },
        onDone: () {
          print('Relay: Harness disconnected');
          harness = null;
          harnessSub = null;
        },
        onError: (Object e) {
          print('Relay: Harness error: $e');
          harness = null;
          harnessSub = null;
        },
      );
    } else {
      // This is the coordinator connection.
      if (coordinator != null) {
        print('Relay: Replacing stale coordinator connection');
        coordinatorSub?.cancel();
        coordinator!.close();
      }
      coordinator = ws;
      print('Relay: Coordinator connected from $remoteAddr');

      coordinatorSub = ws.listen(
        (data) {
          // Forward coordinator → harness.
          if (harness != null) {
            harness!.add(data);
          }
        },
        onDone: () {
          print('Relay: Coordinator disconnected');
          coordinator = null;
          coordinatorSub = null;
        },
        onError: (Object e) {
          print('Relay: Coordinator error: $e');
          coordinator = null;
          coordinatorSub = null;
        },
      );
    }
  }
}
