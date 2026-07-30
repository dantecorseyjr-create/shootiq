import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/services/review_prompt_service.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class RateShootIqPage extends StatefulWidget {
  const RateShootIqPage({super.key});

  @override
  State<RateShootIqPage> createState() => _RateShootIqPageState();
}

class _RateShootIqPageState extends State<RateShootIqPage> {
  bool _loading = true;
  bool _eligible = false;
  int _analyses = 0;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final analyses = await ReviewPromptService.completedAnalyses();
    final eligible = await ReviewPromptService.shouldOfferReview();
    if (!mounted) return;
    setState(() {
      _analyses = analyses;
      _eligible = eligible || analyses > 0;
      _loading = false;
    });
  }

  Future<void> _requestReview() async {
    setState(() => _requesting = true);
    try {
      final inAppReview = InAppReview.instance;
      final available = await inAppReview.isAvailable();

      if (kDebugMode || !available) {
        // Development / simulator placeholder behavior.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Review prompt simulated in development. On a production build, Apple’s in-app review sheet will appear when eligible.',
            ),
          ),
        );
        await ReviewPromptService.markReviewRequested();
        return;
      }

      // Only prompt after meaningful usage (or allow manual override if already used the app).
      if (!await ReviewPromptService.shouldOfferReview() && _analyses < 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Complete a few shot analyses first — then we can ask for a review.',
            ),
          ),
        );
        return;
      }

      await inAppReview.requestReview();
      await ReviewPromptService.markReviewRequested();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for supporting ShootIQ!')),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Rate ShootIQ',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                SettingsInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enjoying ShootIQ?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: ShootIQTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Ratings help more players discover AI coaching. We only ask after you’ve used the app meaningfully.',
                        style: TextStyle(
                          color: ShootIQTheme.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Completed analyses: $_analyses',
                        style: const TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _eligible
                            ? 'You’re eligible to leave a review.'
                            : 'Analyze a few shots first for the best timing.',
                        style: const TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SettingsPrimaryButton(
                  label: 'Rate ShootIQ',
                  isLoading: _requesting,
                  onPressed: _requestReview,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Apple may limit how often the native review dialog can appear.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }
}
