import 'dart:async';

/// Simple log sink for the harness app.
///
/// Broadcasts log entries that the UI can listen to and display.
class HarnessLog {
  final _controller = StreamController<String>.broadcast();

  /// Stream of log entries.
  Stream<String> get entries => _controller.stream;

  /// Adds a log entry with a timestamp prefix.
  void add(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _controller.add('$timestamp $message');
  }

  /// Closes the log stream.
  Future<void> dispose() async {
    await _controller.close();
  }
}
