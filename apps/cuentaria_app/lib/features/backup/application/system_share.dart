import 'package:flutter/services.dart';

/// Hands a text file to the OS share sheet (ADR-0021 §5): one tap, no
/// permissions, lets the user send it to Drive, mail, or WhatsApp.
///
/// Deliberately not `path_provider` + a file-picker: `path_provider`'s app
/// directories are wiped on uninstall, the exact scenario a Backup File
/// exists to survive.
abstract class SystemShare {
  /// Shares [content] as a file named [filename]. [sharePositionOrigin] is
  /// required on iPad — the share sheet's popover anchor — and ignored
  /// elsewhere. Returns whether the user completed a share action.
  Future<bool> shareFile({
    required String filename,
    required String content,
    Rect? sharePositionOrigin,
  });
}

/// Platform-channel-backed [SystemShare]: `ACTION_SEND` on Android,
/// `UIActivityViewController` on iOS.
class MethodChannelSystemShare implements SystemShare {
  static const _channel = MethodChannel('cuentaria/system_share');

  const MethodChannelSystemShare();

  @override
  Future<bool> shareFile({
    required String filename,
    required String content,
    Rect? sharePositionOrigin,
  }) async {
    final completed = await _channel.invokeMethod<bool>('shareFile', {
      'filename': filename,
      'content': content,
      if (sharePositionOrigin != null) ...{
        'originX': sharePositionOrigin.left,
        'originY': sharePositionOrigin.top,
        'originWidth': sharePositionOrigin.width,
        'originHeight': sharePositionOrigin.height,
      },
    });
    return completed ?? false;
  }
}
