import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/services/data_export_service.dart';
import 'package:shootiq/services/export_delivery_service.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class DownloadMyDataPage extends StatefulWidget {
  const DownloadMyDataPage({super.key});

  @override
  State<DownloadMyDataPage> createState() => _DownloadMyDataPageState();
}

class _DownloadMyDataPageState extends State<DownloadMyDataPage> {
  DataExportFormat _format = DataExportFormat.json;
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final file = await DataExportService.buildAccountDataPackage(
        format: _format,
      );
      if (!mounted) return;

      final savedPath = await ExportDeliveryService.deliverFile(
        context,
        file: file,
        subject: 'ShootIQ data export',
        text: 'Your ShootIQ account data export.',
      );
      if (!mounted) return;
      if (savedPath == null) return; // user cancelled save dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export ready (${_format.name.toUpperCase()})'
            ' · ${p.basename(savedPath)}',
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
      title: 'Download My Data',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          SettingsInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'What’s included',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ShootIQTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '• Account email and user id\n'
                  '• Player profile details\n'
                  '• Subscription status\n'
                  '• Shot scores, feedback, and history metadata',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Local basketball videos remain on your device and are not included '
                  'in this download. Future versions may offer an optional media package.',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SettingsInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export format',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ShootIQTheme.textPrimary,
                  ),
                ),
                RadioListTile<DataExportFormat>(
                  value: DataExportFormat.json,
                  groupValue: _format,
                  title: const Text('JSON'),
                  subtitle: const Text('Machine-readable account package'),
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _format = value);
                        },
                ),
                RadioListTile<DataExportFormat>(
                  value: DataExportFormat.zip,
                  groupValue: _format,
                  title: const Text('ZIP'),
                  subtitle: const Text(
                    'Folder package + README (media not included yet)',
                  ),
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
            label: 'Create Download',
            isLoading: _busy,
            onPressed: _export,
          ),
          const SizedBox(height: 10),
          const Text(
            // TODO(backend): swap local package builder for authenticated server export.
            'TODO: connect authenticated backend export when cloud sync ships.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
