import 'js_bridge_context.dart';

void requireBridgeCapability(
  PermissionCheck? permissionCheck,
  String capabilityId,
) {
  if (permissionCheck == null) {
    // No permission check registered: default-deny. Production always
    // registers one from ChatWebViewWidget.
    throw StateError('Permission denied: $capabilityId (no check)');
  }
  if (!permissionCheck(capabilityId)) {
    throw StateError('Permission denied: $capabilityId');
  }
}
