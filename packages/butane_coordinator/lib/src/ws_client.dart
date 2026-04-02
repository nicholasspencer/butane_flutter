import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// A WebSocket client that connects to a BLE test harness instance.
///
/// Supports request/response matching by ID and an events stream
/// for unsolicited messages.
class HarnessClient {
  HarnessClient({
    required this.role,
    required this.host,
    required this.port,
    this.defaultTimeout = const Duration(seconds: 15),
  });

  /// Label for this client (e.g. "central" or "peripheral").
  final String role;

  /// WebSocket server host.
  final String host;

  /// WebSocket server port.
  final int port;

  /// Default timeout for [sendCommand].
  final Duration defaultTimeout;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of unsolicited event messages from the harness.
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  /// Whether the client is currently connected.
  bool get isConnected => _channel != null;

  /// Connect to the harness WebSocket server with retry.
  ///
  /// Retries up to [maxAttempts] times (default 3) with exponential backoff.
  Future<void> connect({int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final uri = Uri.parse('ws://$host:$port');
        final channel = WebSocketChannel.connect(uri);
        await channel.ready;
        _channel = channel;
        _subscription = channel.stream.listen(
          _onMessage,
          onError: _onError,
          onDone: _onDone,
        );
        return;
      } catch (e) {
        if (attempt == maxAttempts) {
          throw TimeoutException(
            'Failed to connect to $role harness at $host:$port '
            'after $maxAttempts attempts: $e',
          );
        }
        await Future<void>.delayed(
          Duration(milliseconds: 200 * pow(2, attempt - 1).toInt()),
        );
      }
    }
  }

  /// Send a command to the harness and wait for a matching response.
  ///
  /// Returns the response data map. Throws [TimeoutException] if no
  /// response is received within [timeout] (defaults to [defaultTimeout]).
  Future<Map<String, dynamic>> sendCommand(
    String action, {
    Map<String, dynamic> params = const {},
    Duration? timeout,
  }) async {
    final channel = _channel;
    if (channel == null) {
      throw StateError('Not connected to $role harness');
    }

    final id = _generateId();
    final message = jsonEncode({
      'type': 'command',
      'id': id,
      'action': action,
      'params': params,
    });

    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    channel.sink.add(message);

    final effectiveTimeout = timeout ?? defaultTimeout;
    try {
      return await completer.future.timeout(
        effectiveTimeout,
        onTimeout: () {
          _pending.remove(id);
          throw TimeoutException(
            'Command "$action" to $role harness (port $port) '
            'timed out after ${effectiveTimeout.inSeconds}s',
          );
        },
      );
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }
  }

  /// Disconnect from the harness.
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Connection closed while waiting for response'),
        );
      }
    }
    _pending.clear();
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'result') {
        final id = data['id'] as String?;
        if (id != null && _pending.containsKey(id)) {
          _pending.remove(id)!.complete(data);
        }
      } else if (type == 'event') {
        _eventController.add(data);
      }
    } catch (_) {
      // Ignore malformed messages.
    }
  }

  void _onError(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  void _onDone() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('$role harness connection closed unexpectedly'),
        );
      }
    }
    _pending.clear();
  }

  static int _counter = 0;
  static String _generateId() {
    _counter++;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '$timestamp-$_counter';
  }
}
