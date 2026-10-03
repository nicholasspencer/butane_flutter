part of '../porcelain.dart';

/// A typed failure reported by a Butane backend.
final class ButaneException implements Exception {
  const ButaneException({
    required this.code,
    required this.message,
    this.platform,
    this.nativeCode,
    this.cause,
  });

  /// The backend-independent classification of this failure.
  final ButaneErrorCode code;

  /// Human-readable context about the failed operation.
  final String message;

  /// The backend that reported this failure, when available.
  final String? platform;

  /// The operating-system code or D-Bus error name, when available.
  final String? nativeCode;

  /// The original backend exception, when available.
  final Object? cause;

  @override
  String toString() {
    final context = [
      if (platform != null) 'platform: $platform',
      if (nativeCode != null) 'nativeCode: $nativeCode',
    ];
    final suffix = context.isEmpty ? '' : ' (${context.join(', ')})';
    return 'ButaneException.${code.name}: $message$suffix';
  }
}
