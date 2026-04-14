import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'harness_connection.dart';

/// A WebSocket client that connects OUT to a relay server and exposes
/// the same interface as [HarnessServer].
///
/// Used on iOS where the device can't reliably serve incoming WS connections
/// due to sandboxing. Instead, the app connects out to a relay running on
/// the Mac, and the coordinator connects to the same relay.
class HarnessClientBridge implements HarnessConnection {
  HarnessClientBridge({required this.relayUrl});

  /// The WebSocket URL to connect to (e.g., ws://192.168.4.1:19101/harness).
  final String relayUrl;

  WebSocket? _socket;

  final _commandController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  @override
  Stream<Map<String, dynamic>> get commands => _commandController.stream;
  @override
  Stream<String> get statusStream => _statusController.stream;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> start() async {
    _statusController.add('Connecting to relay: $relayUrl');

    const maxAttempts = 30;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _socket = await WebSocket.connect(relayUrl);
        _statusController.add('Connected to relay');

        _socket!.listen(
          (data) {
            if (data is String) {
              try {
                final message = jsonDecode(data) as Map<String, dynamic>;
                _commandController.add(message);
                if (_commandHandler != null) {
                  _dispatchCommand(message);
                }
              } catch (e) {
                _statusController.add('Invalid JSON: $e');
              }
            }
          },
          onDone: () {
            _socket = null;
            _statusController.add('Relay disconnected');
          },
          onError: (error) {
            _socket = null;
            _statusController.add('Relay error: $error');
          },
        );
        return;
      } catch (e) {
        _statusController.add(
          'Relay connect attempt $attempt/$maxAttempts failed: $e',
        );
        if (attempt == maxAttempts) {
          _statusController.add(
            'Failed to connect to relay after $maxAttempts attempts',
          );
          rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  @override
  void onCommand(
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler,
  ) {
    _commandHandler = handler;
  }

  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? _commandHandler;

  @override
  void send(Map<String, dynamic> message) {
    if (_socket != null) {
      _socket!.add(jsonEncode(message));
    }
  }

  @override
  void sendEvent({
    required String event,
    required Map<String, dynamic> data,
  }) {
    send({'type': 'event', 'event': event, ...data});
  }

  Future<void> _dispatchCommand(Map<String, dynamic> message) async {
    final action = message['action'] as String?;
    final id = message['id'] as String?;
    final params = message['params'] as Map<String, dynamic>? ?? {};

    final command = <String, dynamic>{
      'action': action,
      ...params,
    };

    try {
      final result = await _commandHandler!(command);
      send({
        'type': 'result',
        if (id != null) 'id': id,
        'action': action,
        'success': true,
        'data': result,
      });
    } catch (e) {
      send({
        'type': 'result',
        if (id != null) 'id': id,
        'action': action,
        'success': false,
        'error': e.toString(),
      });
    }
  }

  @override
  Future<void> stop() async {
    await _socket?.close();
    _socket = null;
    _statusController.add('Bridge stopped');
    await _commandController.close();
    await _statusController.close();
  }
}
