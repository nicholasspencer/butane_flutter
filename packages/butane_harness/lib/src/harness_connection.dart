import 'dart:async';

/// Abstract interface shared by [HarnessServer] and [HarnessClientBridge].
///
/// Both provide WebSocket connectivity to the coordinator and expose
/// the same command/event API. The server mode listens for connections;
/// the client bridge mode connects out to a relay.
abstract class HarnessConnection {
  Stream<Map<String, dynamic>> get commands;
  Stream<String> get statusStream;
  bool get isConnected;

  Future<void> start();
  Future<void> stop();

  void onCommand(
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler,
  );

  void send(Map<String, dynamic> message);

  void sendEvent({
    required String event,
    required Map<String, dynamic> data,
  });
}
