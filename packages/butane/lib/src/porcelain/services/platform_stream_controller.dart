import 'dart:async';

import 'package:butane_platform_interface/butane_platform_interface.dart'
    as api;
import 'package:flutter/foundation.dart';

/// Manages a stream controller that is used to communicate with the host
/// platform.
base class PlatformStreamController<T, P> {
  PlatformStreamController({
    required this.createStream,
    required this.map,
    this.sinkValue,
    this.onListen,
    this.onCancel,
    this.debugLabel,
    api.ButanePlatformInterface? platform,
  }) : _platform = platform;

  final api.ButanePlatformInterface? _platform;

  /// This should call the platform method that returns the stream.
  final Stream<P> Function(api.ButanePlatformInterface platform) createStream;

  /// This should map the platform value to the value that is emitted by the
  /// stream.
  final T Function(P value) map;

  /// This optional function should call the platform method that sinks a value
  /// into the stream.
  final Future<P> Function(api.ButanePlatformInterface platform)? sinkValue;

  /// This should call the platform method that starts the stream.
  final Future<void> Function(api.ButanePlatformInterface platform)? onListen;

  /// This should call the platform method that stops the stream.
  final Future<void> Function(api.ButanePlatformInterface platform)? onCancel;

  final String? debugLabel;

  bool _disposed = false;

  int listenerCount = 0;

  @protected
  P? currentValue;

  Stream<T> get stream {
    assert(
      !_disposed,
      'PlatformStreamController has already been disposed.',
    );

    subscription ??= createStream(platform).listen(onEvent);

    return controller.stream;
  }

  @protected
  api.ButanePlatformInterface get platform =>
      _platform ?? api.ButanePlatformInterface.instance;

  @protected
  StreamSubscription<P>? subscription;

  @protected
  late final StreamController<T> controller = StreamController<T>.broadcast(
    onListen: onListen_,
    onCancel: onCancel_,
  );

  @protected
  void onEvent(P value) {
    currentValue = value;
    controller.sink.add(map(value));
  }

  @protected
  void onListen_() async {
    listenerCount += 1;

    if (listenerCount == 1) {
      await onListen?.call(platform);
    }

    final currentValue = await sinkValue?.call(platform);
    this.currentValue = currentValue;

    if (currentValue != null) {
      controller.sink.add(map(currentValue));
    }
  }

  @protected
  void onCancel_() async {
    listenerCount -= 1;

    if (listenerCount > 0) {
      return;
    }

    await onCancel?.call(platform);
    subscription?.cancel();
    subscription = null;
  }

  void dispose() async {
    _disposed = true;

    await subscription?.cancel();
    await controller.close();
  }
}
