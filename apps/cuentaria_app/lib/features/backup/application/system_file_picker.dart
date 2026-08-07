import 'package:flutter/services.dart';

/// Opens the OS file picker to choose a Backup File to restore (ADR-0021
/// §5): one tap, no permissions, works with whatever the user picked it up
/// from — Drive, mail, or a WhatsApp download.
///
/// Deliberately not a pub.dev plugin, mirroring [SystemShare]: a thin
/// platform channel keeps the surface identical to what's already there
/// instead of pulling in a dependency for one native call per platform.
abstract class SystemFilePicker {
  /// Opens the system file picker and returns the picked file's content, or
  /// null if the user cancelled without picking anything.
  Future<String?> pickFile();
}

/// Platform-channel-backed [SystemFilePicker]: `ACTION_OPEN_DOCUMENT` on
/// Android, `UIDocumentPickerViewController` on iOS.
class MethodChannelSystemFilePicker implements SystemFilePicker {
  static const _channel = MethodChannel('cuentaria/system_file_picker');

  const MethodChannelSystemFilePicker();

  @override
  Future<String?> pickFile() {
    return _channel.invokeMethod<String>('pickFile');
  }
}
