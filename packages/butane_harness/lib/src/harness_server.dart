import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HarnessServer {
  HarnessServer({required this.port});

  final int port;

  HttpServer? _httpServer;
  WebSocket? _client;

  final _commandController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get commands => _commandController.stream;
  Stream<String> get statusStream => _statusController.stream;

  bool get isConnected => _client != null;

  Future<void> start() async {
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _statusController.add('Listening on 0.0.0.0:$port');

    _httpServer!.transform(WebSocketTransformer()).listen(
      _handleConnection,
      onError: (error) {
        _statusController.add('Server error: $error');
      },
    );
  }

  void _handleConnection(WebSocket ws) {
    if (_client != null) {
      ws.close(WebSocketStatus.normalClosure, 'Already connected');
      return;
    }

    _client = ws;
    _statusController.add('Coordinator connected');

    ws.listen(
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
        _client = null;
        _statusController.add('Coordinator disconnected');
      },
      onError: (error) {
        _client = null;
        _statusController.add('Connection error: $error');
      },
    );
  }

  /// Registers a command handler that receives commands and returns results.
  ///
  /// When a command arrives, [handler] is called with a map containing
  /// the `action` and all params. The returned map is sent back as a result.
  void onCommand(
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler,
  ) {
    _commandHandler = handler;
  }

  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? _commandHandler;

  void send(Map<String, dynamic> message) {
    if (_client != null) {
      _client!.add(jsonEncode(message));
    }
  }

  /// Sends an unsolicited event to the connected coordinator.
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

    // Build a flat command map with action + params for the handler.
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

  Future<void> stop() async {
    await _client?.close();
    await _httpServer?.close();
    _client = null;
    _httpServer = null;
    _statusController.add('Server stopped');
    await _commandController.close();
    await _statusController.close();
  }
}
