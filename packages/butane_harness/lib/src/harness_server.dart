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
    _httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _statusController.add('Listening on localhost:$port');

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
  /// When a command arrives, [handler] is called with the command map.
  /// The returned map is sent back as a result message.
  /// If [handler] throws, an error result is sent instead.
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

  Future<void> _dispatchCommand(Map<String, dynamic> command) async {
    final action = command['action'] as String?;
    try {
      final result = await _commandHandler!(command);
      send({
        'type': 'result',
        'action': action,
        'success': true,
        'data': result,
      });
    } catch (e) {
      send({
        'type': 'result',
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
