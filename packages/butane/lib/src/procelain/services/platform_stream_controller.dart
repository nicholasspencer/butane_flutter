import 'dart:async';

import 'package:butane_platform_interface/butane_platform_interface.dart'
    as api;
import 'package:flutter/foundation.dart';

/// Manages a stream controller that is used to communicate with the host
/// platform.
base class PlatformStreamController<T, P> {
  PlatformStreamController({
    required this.createStream,
    required this.onListen,
    required this.map,
    this.createValue,
    this.onCancel,
    api.ButanePlatformInterface? platform,
  }) : _platform = platform;

  final api.ButanePlatformInterface? _platform;

  final Stream<P> Function(api.ButanePlatformInterface platform) createStream;

  final Future<void> Function(api.ButanePlatformInterface platform) onListen;

  final Future<T> Function(api.ButanePlatformInterface platform)? createValue;

  final Future<void> Function(api.ButanePlatformInterface platform)? onCancel;

  final T Function(P value) map;

  Stream<T> get stream => controller.stream;

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
    controller.sink.add(map(value));
  }

  @protected
  void onListen_() async {
    if (subscription != null) {
      final value = await createValue?.call(platform);

      if (value != null) {
        controller.sink.add(value);
      }

      return;
    }

    subscription ??= createStream(platform).listen(onEvent);

    await onListen.call(platform);
  }

  @protected
  void onCancel_() async {
    if (controller.hasListener) {
      return;
    }

    await onCancel?.call(platform);
    subscription?.cancel();
    subscription = null;
  }

  void dispose() async {
    await subscription?.cancel();
    await controller.close();
  }
}
