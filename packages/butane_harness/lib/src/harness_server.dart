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

  void send(Map<String, dynamic> message) {
    if (_client != null) {
      _client!.add(jsonEncode(message));
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
