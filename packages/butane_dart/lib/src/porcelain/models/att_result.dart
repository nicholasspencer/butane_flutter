part of '../porcelain.dart';

/// The result of an ATT (Attribute Protocol) request.
enum AttResult {
  success,
  invalidHandle,
  readNotPermitted,
  writeNotPermitted,
  invalidOffset,
  attributeNotFound,
  unlikelyError;

  /// Converts this porcelain [AttResult] to the platform interface type.
  api.AttResult toApi() {
    switch (this) {
      case AttResult.success:
        return api.AttResult.success;
      case AttResult.invalidHandle:
        return api.AttResult.invalidHandle;
      case AttResult.readNotPermitted:
        return api.AttResult.readNotPermitted;
      case AttResult.writeNotPermitted:
        return api.AttResult.writeNotPermitted;
      case AttResult.invalidOffset:
        return api.AttResult.invalidOffset;
      case AttResult.attributeNotFound:
        return api.AttResult.attributeNotFound;
      case AttResult.unlikelyError:
        return api.AttResult.unlikelyError;
    }
  }

  /// Creates an [AttResult] from the platform interface type.
  factory AttResult.fromApi(api.AttResult result) {
    switch (result) {
      case api.AttResult.success:
        return AttResult.success;
      case api.AttResult.invalidHandle:
        return AttResult.invalidHandle;
      case api.AttResult.readNotPermitted:
        return AttResult.readNotPermitted;
      case api.AttResult.writeNotPermitted:
        return AttResult.writeNotPermitted;
      case api.AttResult.invalidOffset:
        return AttResult.invalidOffset;
      case api.AttResult.attributeNotFound:
        return AttResult.attributeNotFound;
      case api.AttResult.unlikelyError:
        return AttResult.unlikelyError;
    }
  }
}
