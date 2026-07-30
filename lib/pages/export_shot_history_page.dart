import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/services/data_export_service.dart';
import 'package:shootiq/services/export_delivery_service.dart';
import 'package:shootiq/services/shot_history_service.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class ExportShotHistoryPage extends StatefulWidget {
  const ExportShotHistoryPage({super.key});

  @override
  State<ExportShotHistoryPage> createState() => _ExportShotHistoryPageState();
}

class _ExportShotHistoryPageState extends State<ExportShotHistoryPage> {
  ShotHistoryExportFormat _format = ShotHistoryExportFormat.csv;
  bool _loadingSummary = true;
  bool _busy = false;
  int _shotCount = 0;
  String? _lastSummary;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    final shots = await ShotHistoryService.getUserShots(limit: 500);
    if (!mounted) return;
    setState(() {
      _shotCount = shots.length;
      _loadingSummary = false;
    });
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final result = await DataExportService.exportShotHistory(format: _format);
      if (!mounted) return;

      final savedPath = await ExportDeliveryService.deliverFile(
        context,
        file: result.file,
        subject: 'ShootIQ shot history',
        text: result.summary,
      );
      if (!mounted) return;
      if (savedPath == null) return; // user cancelled save dialog

      setState(() => _lastSummary = result.summary);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${result.shotCount} shots as ${_format.name.toUpperCase()}'
            '${savedPath.isNotEmpty ? ' · ${p.basename(savedPath)}' : ''}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Export Shot History',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          SettingsInfoCard(
            child: _loadingSummary
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Export summary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: ShootIQTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_shotCount analyzed shots available on this device.',
                        style: const TextStyle(
                          color: ShootIQTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      if (_lastSummary != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Last export: $_lastSummary',
                          style: const TextStyle(
                            color: ShootIQTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          SettingsInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Format',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ShootIQTheme.textPrimary,
                  ),
                ),
                RadioListTile<ShotHistoryExportFormat>(
                  value: ShotHistoryExportFormat.pdf,
                  groupValue: _format,
                  title: const Text('PDF'),
                  subtitle: const Text(
                    'Readable report (text PDF stand-in until generator ships)',
                  ),
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _format = value);
                        },
                ),
                RadioListTile<ShotHistoryExportFormat>(
                  value: ShotHistoryExportFormat.csv,
                  groupValue: _format,
                  title: const Text('CSV'),
                  subtitle: const Text('Spreadsheet-friendly metrics'),
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _format = value);
                        },
                ),
                RadioListTile<ShotHistoryExportFormat>(
                  value: ShotHistoryExportFormat.json,
                  groupValue: _format,
                  title: const Text('JSON'),
                  subtitle: const Text('Full on-device history payload'),
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _format = value);
                        },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SettingsPrimaryButton(
            label: 'Export History',
            isLoading: _busy,
            onPressed: _shotCount == 0 ? null : _export,
          ),
          const SizedBox(height: 10),
          const Text(
            // TODO(export): implement polished PDF generation and optional media bundle.
            'TODO: upgrade PDF export to a designed multi-page report.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ShootIQTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
