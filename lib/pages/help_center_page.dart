import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/content/help_faq_content.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class HelpCenterPage extends StatefulWidget {
  const HelpCenterPage({super.key});

  @override
  State<HelpCenterPage> createState() => _HelpCenterPageState();
}

class _HelpCenterPageState extends State<HelpCenterPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _iconFor(String name) {
    return switch (name) {
      'rocket' => Icons.rocket_launch_outlined,
      'videocam' => Icons.videocam_outlined,
      'psychology' => Icons.psychology_outlined,
      'score' => Icons.speed_rounded,
      'star' => Icons.workspace_premium_outlined,
      'person' => Icons.person_outline_rounded,
      'build' => Icons.build_outlined,
      _ => Icons.help_outline_rounded,
    };
  }

  List<HelpFaqSection> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return HelpFaqContent.sections;
    return HelpFaqContent.sections
        .map((section) {
          final items = section.items
              .where(
                (item) =>
                    item.question.toLowerCase().contains(q) ||
                    item.answer.toLowerCase().contains(q) ||
                    section.title.toLowerCase().contains(q),
              )
              .toList();
          return HelpFaqSection(
            title: section.title,
            iconName: section.iconName,
            items: items,
          );
        })
        .where((section) => section.items.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _filtered;

    return SettingsSubpageScaffold(
      title: 'Help Center',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search FAQs',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: ShootIQTheme.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (sections.isEmpty)
            const SettingsInfoCard(
              child: Text(
                'No matching articles. Try another search.',
                style: TextStyle(color: ShootIQTheme.textSecondary),
              ),
            )
          else
            for (final section in sections) ...[
              SettingsInfoCard(
                padding: EdgeInsets.zero,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: Icon(
                      _iconFor(section.iconName),
                      color: ShootIQTheme.primaryBlue,
                    ),
                    title: Text(
                      section.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: ShootIQTheme.textPrimary,
                      ),
                    ),
                    children: [
                      for (final item in section.items)
                        ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            item.question,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: ShootIQTheme.textPrimary,
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Text(
                                item.answer,
                                style: const TextStyle(
                                  color: ShootIQTheme.textSecondary,
                                  height: 1.45,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
