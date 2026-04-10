// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Register a beforeunload handler (web only).
void registerBeforeUnload(bool Function() hasUnsavedChanges) {
  html.window.onBeforeUnload.listen((event) {
    if (hasUnsavedChanges()) {
      (event as html.BeforeUnloadEvent).returnValue =
          'You have unsaved changes. Are you sure you want to leave?';
    }
  });
}

/// Download bytes as a file in the browser.
void downloadBytes(List<int> bytes, String filename,
    {String mimeType = 'application/octet-stream'}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

/// Pick a file from the user's device (web only).
/// Returns the file bytes, or null if the user cancelled.
void pickFileBytes({
  required String accept,
  required void Function(Uint8List bytes) onPicked,
}) {
  final input = html.FileUploadInputElement()..accept = accept;
  input.click();
  input.onChange.listen((event) {
    final file = input.files?.first;
    if (file == null) return;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    reader.onLoadEnd.listen((_) {
      onPicked(Uint8List.fromList(reader.result as List<int>));
    });
  });
}
