import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Bundled sample shot shown from "Try Demo Analysis" — works for every
/// user with no server round-trip, since it ships inside the app itself.
class DemoAnalysisService {
  DemoAnalysisService._();

  static const _videoAsset = 'assets/demo/demo_shot.mp4';
  static const _resultsAsset = 'assets/demo/demo_results.json';
  static const _videoPlaceholder = 'DEMO_ASSET_VIDEO';

  /// Copies the bundled demo video to a stable local path (once) and
  /// returns a results map with every video-URL field pointed at it —
  /// same shape `ResultsPage` already expects from a live `/analyze` call.
  static Future<Map<String, dynamic>> loadResults() async {
    final videoPath = await _ensureVideoOnDisk();

    final raw = await rootBundle.loadString(_resultsAsset);
    final decoded = jsonDecode(raw);
    final map = Map<String, dynamic>.from(decoded as Map);

    for (final key in map.keys.toList()) {
      if (map[key] == _videoPlaceholder) {
        map[key] = videoPath;
      }
    }
    return map;
  }

  static Future<String> _ensureVideoOnDisk() async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = File(p.join(dir.path, 'demo_shot.mp4'));
    if (!await dest.exists()) {
      final bytes = await rootBundle.load(_videoAsset);
      await dest.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    }
    return dest.path;
  }
}
