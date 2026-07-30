import 'dart:io';

import 'package:file_selector/file_selector.dart' hide XFile;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

/// Delivers an exported file to the user (Save dialog on desktop, share on mobile).
class ExportDeliveryService {
  ExportDeliveryService._();

  /// Returns the saved path on desktop, the temp path after sharing on mobile,
  /// or `null` if the user cancelled the save dialog.
  static Future<String?> deliverFile(
    BuildContext context, {
    required File file,
    required String subject,
    String? text,
  }) async {
    final suggestedName = p.basename(file.path);

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final location = await getSaveLocation(suggestedName: suggestedName);
      if (location == null) return null;
      await file.copy(location.path);
      return location.path;
    }

    // iPhone/iPad require a non-empty origin inside the screen bounds.
    final box = context.findRenderObject() as RenderBox?;
    final size = MediaQuery.sizeOf(context);
    final Rect origin;
    if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
      origin = box.localToGlobal(Offset.zero) & box.size;
    } else {
      origin = Rect.fromLTWH(0, 0, size.width, size.height / 2);
    }

    await Share.shareXFiles(
      [XFile(file.path, name: suggestedName)],
      subject: subject,
      text: text,
      sharePositionOrigin: origin,
    );
    return file.path;
  }
}
