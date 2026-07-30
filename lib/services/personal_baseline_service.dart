import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/shot_history_service.dart';

/// Personalized biomechanics baseline built from historical analyses.
///
/// Architecture notes:
/// - Every completed analysis stores baseline_features + confidence in
///   `metrics_json` (see [ShotHistoryService.saveAnalyzedShot]).
/// - After [minSamples] analyses (first 5 shots), [recompute] builds a
///   personal baseline used by Progress comparisons.
/// - Personalized scoring is gated by [personalizedScoringEnabled] (default
///   false) so displayed Results scores stay ideal-biomechanics based until
///   product enables the soft consistency relief path.
class PersonalBaselineService {
  PersonalBaselineService._();

  /// Progress unlocks baseline comparisons after the first 5 analyzed shots.
  static const minSamples = 5;

  /// Keep false — do not change displayed scores until explicitly enabled.
  static const personalizedScoringEnabled = false;

  static const _fileName = 'personal_baseline.json';

  static Future<File> _fileForUser(String userId) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'shootiq_baselines'));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    return File(p.join(folder.path, '${userId}_$_fileName'));
  }

  static Future<Map<String, dynamic>?> load() async {
    final user = AuthService.currentUser;
    if (user == null) return null;
    final file = await _fileForUser(user.id);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      // ignore: avoid_print
      print('PersonalBaseline load error: $e');
    }
    return null;
  }

  static Future<void> save(Map<String, dynamic> baseline) async {
    final user = AuthService.currentUser;
    if (user == null) return;
    final file = await _fileForUser(user.id);
    final payload = {
      ...baseline,
      'user_id': user.id,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }

  /// Baseline payload safe to send to `/analyze` (null if not ready / disabled).
  static Future<Map<String, dynamic>?> baselineForAnalyzeRequest() async {
    final baseline = await load();
    if (baseline == null) return null;
    if (baseline['ready'] != true) return null;
    // Always send when ready so the server can record eligibility metadata.
    // Soft score adjustments remain gated by PERSONALIZED_SCORING_ENABLED.
    return baseline;
  }

  /// Recompute from history after each saved analysis.
  static Future<Map<String, dynamic>?> recompute({
    List<ShotRecord>? shots,
  }) async {
    final history =
        shots ?? await ShotHistoryService.getUserShots(limit: 200);
    if (history.length < minSamples) {
      final stub = <String, dynamic>{
        'version': 1,
        'ready': false,
        'sample_count': history.length,
        'min_samples': minSamples,
        'consistency': 0.0,
        'features': <String, dynamic>{},
        'scores': <String, dynamic>{},
      };
      await save(stub);
      // ignore: avoid_print
      print(
        'PersonalBaseline: ${history.length}/$minSamples samples '
        '(not ready yet)',
      );
      return stub;
    }

    final samples = history
        .map(_sampleFromShot)
        .whereType<Map<String, dynamic>>()
        .toList();
    if (samples.length < minSamples) {
      final stub = <String, dynamic>{
        'version': 1,
        'ready': false,
        'sample_count': samples.length,
        'min_samples': minSamples,
      };
      await save(stub);
      return stub;
    }

    final featureSeries = <String, List<double>>{};
    final scoreSeries = <String, List<double>>{};
    final weights = <String, List<double>>{};

    for (final sample in samples) {
      final feats = Map<String, dynamic>.from(
        (sample['features'] as Map?) ?? const {},
      );
      final scores = Map<String, dynamic>.from(
        (sample['scores'] as Map?) ?? const {},
      );
      final conf = Map<String, dynamic>.from(
        (sample['confidence'] as Map?) ?? const {},
      );
      final avgConf = conf.isEmpty
          ? 0.7
          : conf.values
                  .whereType<num>()
                  .map((n) => n.toDouble())
                  .fold<double>(0, (a, b) => a + b) /
              conf.values.whereType<num>().length;

      for (final entry in feats.entries) {
        final value = entry.value;
        if (value is! num) continue;
        featureSeries.putIfAbsent(entry.key, () => <double>[]).add(value.toDouble());
        weights.putIfAbsent(entry.key, () => <double>[]).add(avgConf);
      }
      for (final entry in scores.entries) {
        final value = entry.value;
        if (value is! num) continue;
        scoreSeries.putIfAbsent(entry.key, () => <double>[]).add(value.toDouble());
      }
    }

    Map<String, dynamic> stats(List<double> values, [List<double>? w]) {
      final sorted = [...values]..sort();
      final mean = (w != null && w.length == values.length)
          ? _weightedMean(values, w)
          : values.reduce((a, b) => a + b) / values.length;
      return {
        'mean': _round(mean),
        'median': _round(_percentile(sorted, 0.5)),
        'std': _round(_stdDev(values, mean)),
        'p25': _round(_percentile(sorted, 0.25)),
        'p75': _round(_percentile(sorted, 0.75)),
        'n': values.length,
      };
    }

    final minFeatureN = (minSamples / 4).ceil().clamp(5, minSamples);
    final features = <String, dynamic>{};
    for (final entry in featureSeries.entries) {
      if (entry.value.length < minFeatureN) continue;
      features[entry.key] = stats(entry.value, weights[entry.key]);
    }
    final scores = <String, dynamic>{};
    for (final entry in scoreSeries.entries) {
      if (entry.value.length < minFeatureN) continue;
      scores[entry.key] = stats(entry.value);
    }

    final cvs = <double>[];
    for (final raw in features.values) {
      final s = Map<String, dynamic>.from(raw as Map);
      final mean = (s['mean'] as num).abs().toDouble();
      final std = (s['std'] as num).toDouble();
      cvs.add((std / (mean < 1e-6 ? 1.0 : mean)).clamp(0.0, 1.5));
    }
    final consistency = cvs.isEmpty
        ? 0.0
        : (1.0 - (cvs.reduce((a, b) => a + b) / cvs.length)).clamp(0.0, 1.0);

    final baseline = <String, dynamic>{
      'version': 1,
      'ready': true,
      'sample_count': samples.length,
      'min_samples': minSamples,
      'consistency': _round(consistency),
      'features': features,
      'scores': scores,
      'personalized_scoring_enabled': personalizedScoringEnabled,
    };
    await save(baseline);
    // ignore: avoid_print
    print(
      'PersonalBaseline READY samples=${samples.length} '
      'consistency=${baseline['consistency']} '
      'scoringEnabled=$personalizedScoringEnabled',
    );
    return baseline;
  }

  static Map<String, dynamic>? _sampleFromShot(ShotRecord shot) {
    final metrics = shot.metricsJson;
    final features = Map<String, dynamic>.from(
      (metrics['baseline_features'] as Map?) ?? const {},
    );
    final confidence = Map<String, dynamic>.from(
      (metrics['measurement_confidence'] as Map?) ?? const {},
    );

    // Fallback: derive sparse features from stored scores when older shots
    // predate baseline_features.
    if (features.isEmpty) {
      features['overall_score'] = shot.overallScore.toDouble();
      features['release_point_score'] = shot.releasePoint.toDouble();
      features['elbow_alignment_score'] = shot.elbowAlignment.toDouble();
      features['knee_bend_score'] = shot.kneeBend.toDouble();
      features['balance_score'] = shot.balance.toDouble();
      features['follow_through_score'] = shot.followThrough.toDouble();
    }

    // Pull confidence from breakdown when metrics bag lacks it.
    if (confidence.isEmpty) {
      for (final item in shot.breakdown) {
        if (item.confidence != null) {
          confidence[item.category] = item.confidence;
        }
      }
    }

    return {
      'features': features,
      'confidence': confidence,
      'scores': {
        'overall': shot.overallScore,
        'elbow_alignment': shot.elbowAlignment,
        'knee_bend': shot.kneeBend,
        'balance': shot.balance,
        'follow_through': shot.followThrough,
        'release_point': shot.releasePoint,
      },
      'phase_landmarks': metrics['phase_landmarks'],
    };
  }

  static double _weightedMean(List<double> values, List<double> weights) {
    var nume = 0.0;
    var deno = 0.0;
    for (var i = 0; i < values.length; i++) {
      nume += values[i] * weights[i];
      deno += weights[i];
    }
    return deno == 0 ? 0 : nume / deno;
  }

  static double _stdDev(List<double> values, double mean) {
    if (values.length < 2) return 0;
    var sum = 0.0;
    for (final v in values) {
      final d = v - mean;
      sum += d * d;
    }
    return math.sqrt(sum / values.length);
  }

  static double _percentile(List<double> sorted, double q) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final pos = (sorted.length - 1) * q;
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    final t = pos - lo;
    return sorted[lo] * (1 - t) + sorted[hi] * t;
  }

  static double _round(double value) =>
      double.parse(value.toStringAsFixed(4));
}
