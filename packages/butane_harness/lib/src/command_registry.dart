/// The transport-agnostic harness command layer.
///
/// A role (central/peripheral) registers its command vocabulary here once;
/// the WebSocket control plane (the coordinator's channel) and the leonard
/// extension (`ext.exploration.*`, the burn's drive channel) are two
/// frontends over the same table — one vocabulary, one dispatch, no drift.
library;

/// Handles one harness command: the full params map in, a JSON-safe result
/// map out. Thrown [ArgumentError]/[StateError]s are the failure contract —
/// each frontend renders them in its own envelope.
typedef CommandHandler = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> params,
);

/// One named harness command: its wire [action] name (snake_case, doubles as
/// the leonard tool name), a human/model-readable [description], and the
/// [handler].
class HarnessCommand {
  const HarnessCommand({
    required this.action,
    required this.description,
    required this.handler,
  });

  /// The wire name (`scan`, `add_service`, …). Must be a bare snake_case
  /// token — it is also exposed verbatim as the leonard tool name.
  final String action;

  /// What the command does and the params it takes (surfaced to the agent as
  /// the tool description).
  final String description;

  /// The command implementation.
  final CommandHandler handler;
}

/// The command table for one harness role.
class HarnessCommandRegistry {
  final Map<String, HarnessCommand> _commands = {};

  /// The number of dispatches currently executing (the busy-state signal for
  /// the leonard extension: a drive/coordinator never observes mid-command).
  int _inFlight = 0;

  /// Whether any command is currently executing.
  bool get isBusy => _inFlight > 0;

  /// The registered commands, in registration order.
  List<HarnessCommand> get commands => List.unmodifiable(_commands.values);

  /// Registers [command]. Throws [StateError] on a duplicate action name.
  void register(HarnessCommand command) {
    if (_commands.containsKey(command.action)) {
      throw StateError('duplicate harness command: ${command.action}');
    }
    _commands[command.action] = command;
  }

  /// Registers every command in [commands].
  void registerAll(Iterable<HarnessCommand> commands) {
    commands.forEach(register);
  }

  /// Dispatches [action] with [params]. An unknown action returns the same
  /// `{'success': false, 'error': …}` shape the WS switch used to produce;
  /// handler exceptions propagate to the frontend (the WS server and the
  /// leonard tool each wrap them in their own error envelope).
  Future<Map<String, dynamic>> dispatch(
    String? action,
    Map<String, dynamic> params,
  ) async {
    final command = action == null ? null : _commands[action];
    if (command == null) {
      return {'success': false, 'error': 'Unknown action: $action'};
    }
    _inFlight++;
    try {
      return await command.handler(params);
    } finally {
      _inFlight--;
    }
  }
}
