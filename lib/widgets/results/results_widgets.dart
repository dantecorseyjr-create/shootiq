import 'package:flutter/material.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

/// Large circular shot score card for analysis results.
class ResultsScoreCard extends StatelessWidget {
  const ResultsScoreCard({
    super.key,
    required this.score,
    this.maxScore = 100,
    this.label = 'Above average',
  });

  final int score;
  final int maxScore;
  final String label;

  @override
  Widget build(BuildContext context) {
    final progress = (score / maxScore).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        color: PremiumColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PremiumColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Shot Score',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: PremiumColors.subtitle,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                    backgroundColor: PremiumColors.cardBorder,
                    color: PremiumColors.accentOrange,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        color: PremiumColors.title,
                        height: 1,
                        letterSpacing: -1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Out of $maxScore',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: PremiumColors.subtitle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PremiumColors.accentOrange,
            ),
          ),
        ],
      ),
    );
  }
}

/// Breakdown metric card used in shot analysis results.
class ResultsBreakdownCard extends StatelessWidget {
  const ResultsBreakdownCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.percent,
    required this.description,
  });

  final String emoji;
  final String title;
  final int percent;
  final String description;

  @override
  Widget build(BuildContext context) {
    final needsWork = percent < 70;
    final accent =
        needsWork ? PremiumColors.redAccent : PremiumColors.accentOrange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PremiumColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: needsWork ? PremiumColors.redBorder : PremiumColors.cardBorder,
          width: needsWork ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22, height: 1)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PremiumColors.title,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: PremiumColors.cardBorder,
              color: accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: needsWork
                  ? PremiumColors.redAccent
                  : PremiumColors.subtitle,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Video preview with AI tracking overlay label.
class ResultsVideoPreview extends StatelessWidget {
  const ResultsVideoPreview({super.key});

  static const _assetPath = 'assets/images/results.png';

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 260,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _assetPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: PremiumColors.cardBackground,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Image failed: $error\n$_assetPath',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: PremiumColors.subtitle,
                      height: 1.35,
                    ),
                  ),
                );
              },
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'AI Tracking Complete',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coach recommendation card for analysis results.
class ResultsCoachCard extends StatelessWidget {
  const ResultsCoachCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PremiumColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🤖', style: TextStyle(fontSize: 28, height: 1)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Coach Recommendation',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PremiumColors.title,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: PremiumColors.subtitle,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
