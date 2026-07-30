import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/content/legal_content.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Privacy Policy',
      child: Markdown(
        data: LegalContent.privacyPolicyMarkdown,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        onTapLink: (text, href, title) async {
          if (href == null) return;
          final uri = Uri.tryParse(href);
          if (uri == null) return;
          await launchUrl(uri);
        },
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          h1: const TextStyle(
            color: ShootIQTheme.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
          h2: const TextStyle(
            color: ShootIQTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          h3: const TextStyle(
            color: ShootIQTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          p: const TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 15,
            height: 1.45,
          ),
          listBullet: const TextStyle(color: ShootIQTheme.textSecondary),
          strong: const TextStyle(
            color: ShootIQTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          a: const TextStyle(
            color: ShootIQTheme.primaryBlue,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
