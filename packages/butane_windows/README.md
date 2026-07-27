# butane_windows

A new Flutter plugin project.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/to/develop-plugins),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Windows central semantics

`readRssi` returns the most recent advertisement RSSI snapshot cached by the
native watcher. The snapshot is accepted for 30 seconds; a missing or older
snapshot raises `rssi-unavailable`. Windows does not expose a live
per-connection RSSI read.

`requestMtu(target)` validates the common target range, but WinRT exposes no
client-side ATT MTU request. Windows therefore returns `GattSession.MaxPduSize`,
the actual negotiated/effective MTU, following `butane_flutter-beo`.

Characteristic writes use the requested with-response or without-response
mode. Descriptor writes call `GattDescriptor.WriteValueAsync`; values are not
silently discarded. These writes are the Windows half of `butane_flutter-kr7`.
