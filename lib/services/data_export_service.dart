import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/local_shot_history_store.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:shootiq/services/subscription_service.dart';

enum DataExportFormat { json, zip }

enum ShotHistoryExportFormat { pdf, csv, json }

class DataExportService {
  DataExportService._();

  /// Builds an account data package (profile + settings + shot metrics).
  ///
  /// Local videos are listed by path but **not** embedded.
  /// TODO(backend): replace local package with authenticated server export API.
  static Future<File> buildAccountDataPackage({
    required DataExportFormat format,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('Sign in to download your data.');
    }

    final shots = await LocalShotHistoryStore.loadForUser(user.id);
    final status = await SubscriptionService.subscriptionStatus();
    final plan = await SubscriptionService.currentPlan();
    final profile = ProfileService.current;

    final payload = <String, dynamic>{
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'export_version': 1,
      'user': {
        'id': user.id,
        'email': user.email,
      },
      'profile': profile?.toJson(),
      'subscription': {
        'status': status,
        'plan': plan?.id.name,
        'label': await SubscriptionService.statusLabel(),
        'trial_ends_at':
            (await SubscriptionService.trialEndsAt())?.toIso8601String(),
        'expires_at':
            (await SubscriptionService.expiresAt())?.toIso8601String(),
      },
      'shots': shots.map(_shotSummary).toList(),
      'notes': {
        'videos':
            'Basketball videos remain on your device and are not included in this export.',
        // TODO(backend): when cloud export supports media, document opt-in here.
      },
    };

    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

    if (format == DataExportFormat.json) {
      final file = File(p.join(dir.path, 'shootiq_data_$stamp.json'));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
        flush: true,
      );
      return file;
    }

    // Lightweight ZIP-compatible package: JSON + README (no media).
    // TODO(backend): generate a true compressed archive with optional media.
    final folder = Directory(p.join(dir.path, 'shootiq_export_$stamp'));
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await folder.create(recursive: true);
    await File(p.join(folder.path, 'account_data.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await File(p.join(folder.path, 'README.txt')).writeAsString(
      'ShootIQ data export\n'
      'Generated: ${payload['exported_at']}\n\n'
      'This package includes account, profile, subscription status, and shot '
      'metrics. Local basketball videos are not included.\n',
      flush: true,
    );

    // For now return the JSON companion as the shareable artifact.
    final companion = File(p.join(dir.path, 'shootiq_data_$stamp.zip.json'));
    await companion.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'format': 'zip-manifest',
        'folder': folder.path,
        'files': ['account_data.json', 'README.txt'],
        'payload': payload,
      }),
      flush: true,
    );
    return companion;
  }

  /// Exports shot history in CSV or JSON. PDF is a structured text placeholder.
  ///
  /// TODO(export): wire a real PDF generator (e.g. `pdf` package) for polished reports.
  static Future<({File file, int shotCount, String summary})> exportShotHistory({
    required ShotHistoryExportFormat format,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) {
      throw StateError('Sign in to export shot history.');
    }

    final shots = await LocalShotHistoryStore.loadForUser(user.id);
    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final avg = shots.isEmpty
        ? 0
        : (shots.map((s) => s.overallScore).reduce((a, b) => a + b) /
                shots.length)
            .round();
    final summary =
        '${shots.length} shots · avg score $avg · exported ${DateFormat.yMMMd().format(DateTime.now())}';

    switch (format) {
      case ShotHistoryExportFormat.json:
        final file = File(p.join(dir.path, 'shootiq_history_$stamp.json'));
        await file.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'exported_at': DateTime.now().toUtc().toIso8601String(),
            'summary': summary,
            'shots': shots.map((s) => s.toJson()).toList(),
          }),
          flush: true,
        );
        return (file: file, shotCount: shots.length, summary: summary);

      case ShotHistoryExportFormat.csv:
        final file = File(p.join(dir.path, 'shootiq_history_$stamp.csv'));
        final buffer = StringBuffer(
          'id,created_at,overall_score,elbow,knee,balance,follow_through,release,shot_type,issues\n',
        );
        for (final shot in shots) {
          buffer.writeln(
            [
              _csv(shot.id),
              _csv(shot.createdAt.toIso8601String()),
              shot.overallScore,
              shot.elbowAlignment,
              shot.kneeBend,
              shot.balance,
              shot.followThrough,
              shot.releasePoint,
              _csv(shot.shotType ?? ''),
              _csv(shot.issues.join('; ')),
            ].join(','),
          );
        }
        await file.writeAsString(buffer.toString(), flush: true);
        return (file: file, shotCount: shots.length, summary: summary);

      case ShotHistoryExportFormat.pdf:
        // TODO(export): replace plain-text PDF stand-in with real PDF rendering.
        final file = File(p.join(dir.path, 'shootiq_history_$stamp.pdf.txt'));
        final lines = <String>[
          'ShootIQ Shot History',
          summary,
          '',
          for (final shot in shots)
            '${DateFormat.yMMMd().add_jm().format(shot.createdAt)}  '
                'score ${shot.overallScore}  '
                'elbow ${shot.elbowAlignment}  knee ${shot.kneeBend}  '
                'balance ${shot.balance}  follow ${shot.followThrough}',
        ];
        await file.writeAsString(lines.join('\n'), flush: true);
        return (file: file, shotCount: shots.length, summary: summary);
    }
  }

  static Map<String, dynamic> _shotSummary(ShotRecord shot) {
    return {
      'id': shot.id,
      'created_at': shot.createdAt.toIso8601String(),
      'overall_score': shot.overallScore,
      'elbow_alignment': shot.elbowAlignment,
      'knee_bend': shot.kneeBend,
      'balance': shot.balance,
      'follow_through': shot.followThrough,
      'release_point': shot.releasePoint,
      'issues': shot.issues,
      'recommendations': shot.recommendations,
      'local_video_path': shot.videoUrl,
      'includes_video_bytes': false,
    };
  }

  static String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}
