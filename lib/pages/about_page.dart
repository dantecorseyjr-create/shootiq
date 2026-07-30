import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';
import 'package:shootiq/widgets/shootiq_logo.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    final version = _info?.version ?? '1.0.0';
    final build = _info?.buildNumber ?? '1';

    return SettingsSubpageScaffold(
      title: 'About ShootIQ',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          const Center(child: ShootIQLogo(size: 96)),
          const SizedBox(height: 18),
          const Text(
            'ShootIQ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: ShootIQTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'AI Basketball Shooting Coach',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 24),
          SettingsInfoCard(
            child: Column(
              children: [
                _metaRow('Version', version),
                const Divider(height: 24),
                _metaRow('Build', build),
                const Divider(height: 24),
                _metaRow('Copyright', '© ${DateTime.now().year} ShootIQ'),
                const Divider(height: 24),
                _metaRow('Developer', 'ShootIQ'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'ShootIQ helps players improve shooting mechanics with on-device video, temporary AI analysis, and personalized coaching feedback.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ShootIQTheme.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: ShootIQTheme.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
