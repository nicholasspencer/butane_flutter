/// The butane Leonard extension — the harness command frontend.
///
/// Reflects the [HarnessCommandRegistry] vocabulary as `butane.*` tools
/// (`ext.exploration.butane.<action>`), serializes the active role's
/// synchronous state snapshot as the `extensions.butane` perception
/// fragment, and gates stability on in-flight command dispatches — so a
/// `leonard_drive` scenario (or, later, the agent loop) never observes
/// mid-command.
library;

import 'package:genesis_perception/genesis_perception.dart';
import 'package:leonard_contract/leonard_contract.dart';

import 'command_registry.dart';

/// Leonard extension over the harness command layer.
class ButaneLeonardExtension extends LeonardExtension with PerceptionExtension {
  /// Creates the extension over [registry] (the role's command table) and
  /// [snapshot] (the role's synchronous perception snapshot).
  ButaneLeonardExtension({
    required HarnessCommandRegistry registry,
    required Map<String, Object?> Function() snapshot,
  })  : _registry = registry,
        _snapshot = snapshot;

  final HarnessCommandRegistry _registry;
  final Map<String, Object?> Function() _snapshot;

  @override
  String get namespace => 'butane';

  @override
  List<LeonardTool> get tools => [
        for (final command in _registry.commands)
          _CommandTool(_registry, command),
      ];

  @override
  Future<void> initialize(ExtensionContext ctx) async {}

  @override
  Future<BusyState> busyState() async => _registry.isBusy
      ? const BusyState(isBusy: true, reason: 'harness command in flight')
      : BusyState.idle;

  @override
  Future<void> onActionExecuted(ExecutedAction action) async {}

  @override
  Future<void> dispose() async {}

  @override
  Seed buildPerception() {
    final snapshot = _snapshot();
    return Node(
      'butane',
      children: [
        for (final entry in snapshot.entries) Field(entry.key, entry.value),
      ],
    );
  }
}

/// One harness command surfaced as a leonard tool. Dispatches through the
/// registry (not the bare handler) so the in-flight busy signal covers tool
/// calls.
class _CommandTool extends LeonardTool {
  _CommandTool(this._registry, this._command);

  final HarnessCommandRegistry _registry;
  final HarnessCommand _command;

  @override
  String get name => _command.action;

  @override
  String get description => _command.description;

  @override
  JsonSchema get inputSchema => const JsonSchema(<String, Object?>{
        'type': 'object',
      });

  @override
  Future<ToolResult> call(Map<String, Object?> args) async {
    try {
      final result = await _registry.dispatch(
        _command.action,
        Map<String, dynamic>.from(args),
      );
      return ToolResult(ok: true, value: result);
    } on ArgumentError catch (e) {
      return ToolResult(ok: false, error: '${e.message}');
    } on StateError catch (e) {
      return ToolResult(ok: false, error: e.message);
    } on Object catch (e) {
      // BLE platform failures (timeouts, unauthorized adapter, …) are a
      // failed tool call, not an extension crash.
      return ToolResult(ok: false, error: e.toString());
    }
  }
}
