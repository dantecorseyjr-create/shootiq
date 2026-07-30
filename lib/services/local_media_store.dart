import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Keeps basketball shot videos on the device only (never Supabase Storage).
class LocalMediaStore {
  LocalMediaStore._();

  static Future<Directory> _userDir(String userId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'shootiq_media', userId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Copy a local capture/upload into durable Documents storage.
  static Future<String> persistLocalVideo({
    required String userId,
    required File source,
    required String shotId,
    String suffix = 'original',
  }) async {
    final dir = await _userDir(userId);
    final ext = p.extension(source.path).isNotEmpty
        ? p.extension(source.path)
        : '.mp4';
    final dest = File(p.join(dir.path, '${shotId}_$suffix$ext'));
    if (p.equals(source.path, dest.path)) return dest.path;
    await source.copy(dest.path);
    return dest.path;
  }

  /// Best-effort download of a temporary FastAPI media URL onto the device.
  static Future<String?> downloadToDevice({
    required String userId,
    required String shotId,
    required String url,
    String suffix = 'analysis',
  }) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    try {
      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(minutes: 2),
          );
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final dir = await _userDir(userId);
      final dest = File(p.join(dir.path, '${shotId}_$suffix.mp4'));
      await dest.writeAsBytes(response.bodyBytes, flush: true);
      return dest.path;
    } catch (e) {
      // ignore: avoid_print
      print('LocalMediaStore download skipped: $e');
      return null;
    }
  }

  static Future<void> deletePath(String? path) async {
    if (path == null || path.isEmpty || path.startsWith('http')) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      // ignore: avoid_print
      print('LocalMediaStore delete warning: $e');
    }
  }
}
