/// Pure-Dart reactive BLE porcelain: [CentralManager], [PeripheralManager],
/// [PeerManager], and the reactive model tree. No Flutter dependency, so it
/// runs from any Dart context — CLI tools, server-side apps, provisioning
/// scripts.
///
/// Do NOT import this alongside `package:butane_dart/interface.dart` in the
/// same library without a prefix: the porcelain and the abstraction both
/// declare `MutableService` / `CharacteristicProperties` (the porcelain uses
/// rich `UuidIdentifier`-based types; the abstraction uses raw `String`s), so
/// an unprefixed co-import collides. Import one, or prefix the other.
library;

export 'src/porcelain/porcelain.dart';
