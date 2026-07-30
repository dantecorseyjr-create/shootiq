import 'package:flutter/material.dart';
import 'package:shootiq/widgets/improve/improve_widgets.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

/// Step card for the AI Analyzer how-it-works section.
class AnalyzerStepCard extends StatelessWidget {
  const AnalyzerStepCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.description,
  });

  final String emoji;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PremiumColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PremiumColors.cardBorder),
        boxShadow: ImproveShadows.card,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 32, height: 1.1)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: PremiumColors.title,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
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

/// Left-aligned section title for analyzer content blocks.
class AnalyzerSectionTitle extends StatelessWidget {
  const AnalyzerSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: PremiumColors.title,
        height: 1.2,
        letterSpacing: -0.4,
      ),
    );
  }
}

/// Centered analyzer intro title (34pt bold).
class AnalyzerIntroTitle extends StatelessWidget {
  const AnalyzerIntroTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: PremiumColors.title,
            height: 1.15,
            letterSpacing: -0.8,
          ),
    );
  }
}
