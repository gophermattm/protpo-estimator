import 'dart:typed_data';

/// Stub for non-web platforms — these are no-ops.
void registerBeforeUnload(bool Function() hasUnsavedChanges) {}

void downloadBytes(List<int> bytes, String filename,
    {String mimeType = 'application/octet-stream'}) {}

void pickFileBytes({
  required String accept,
  required void Function(Uint8List bytes) onPicked,
}) {}
