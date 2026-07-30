import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/models/shot_record.dart';

/// On-device shot history (scores, feedback, local video paths).
///
/// Authoritative store for shot results — basketball videos and analysis
/// rows are never persisted in Supabase.
class LocalShotHistoryStore {
  LocalShotHistoryStore._();

  static const _fileName = 'shot_history.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  static Future<List<ShotRecord>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      final docsPath = file.parent.path;
      return decoded
          .whereType<Map>()
          .map((row) => ShotRecord.fromJson(Map<String, dynamic>.from(row)))
          .map((shot) => _rebaseMediaPaths(shot, docsPath))
          .toList();
    } catch (e) {
      // ignore: avoid_print
      print('LocalShotHistoryStore load error: $e');
      return const [];
    }
  }

  /// Rewrites on-device media paths onto the current app container.
  ///
  /// iOS (and Android, less often) assigns a new sandbox container path on
  /// every reinstall, so absolute paths saved under a previous container
  /// (e.g. via `flutter run` during development) stop resolving even though
  /// the file is still there under the new container. Every stored path was
  /// written by [LocalMediaStore] as `<docs>/shootiq_media/<userId>/<file>`,
  /// so rejoin that stable suffix onto the *current* Documents directory.
  static ShotRecord _rebaseMediaPaths(ShotRecord shot, String docsPath) {
    String? rebase(String? path) {
      if (path == null || path.isEmpty || path.startsWith('http')) {
        return path;
      }
      const marker = 'shootiq_media';
      final segments = p.split(path);
      final idx = segments.lastIndexOf(marker);
      if (idx == -1 || idx + 1 >= segments.length) return path;
      return p.joinAll([docsPath, ...segments.sublist(idx)]);
    }

    return shot.copyWith(
      videoUrl: rebase(shot.videoUrl),
      analysisVideoUrl: rebase(shot.analysisVideoUrl),
      skeletonVideoUrl: rebase(shot.skeletonVideoUrl),
      slowMotionVideoUrl: rebase(shot.slowMotionVideoUrl),
    );
  }

  static Future<List<ShotRecord>> loadForUser(String userId) async {
    final all = await loadAll();
    final mine = all.where((shot) => shot.userId == userId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return mine;
  }

  static Future<void> upsert(ShotRecord record) async {
    final all = await loadAll();
    final next = <ShotRecord>[
      record,
      ...all.where((shot) => shot.id != record.id),
    ];
    await _writeAll(next);
  }

  static Future<void> removeById(String id) async {
    final all = await loadAll();
    final next = all.where((shot) => shot.id != id).toList();
    await _writeAll(next);
  }

  static Future<void> _writeAll(List<ShotRecord> records) async {
    final file = await _file();
    final payload = records.map((shot) => shot.toJson()).toList();
    await file.writeAsString(jsonEncode(payload), flush: true);
  }
}
