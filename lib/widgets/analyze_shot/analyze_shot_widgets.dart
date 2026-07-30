import 'package:flutter/material.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

/// Hero illustration for the analyze-shot onboarding screen.
class AnalyzeShotHero extends StatelessWidget {
  const AnalyzeShotHero({super.key});

  static const _assetPath = 'assets/images/analyze_shot.png';
  static const _height = 280.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        _assetPath,
        height: _height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Container(
            height: _height,
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PremiumColors.cardBackground,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              'Image failed: $error\n$_assetPath',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: PremiumColors.subtitle,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyzeShotPlaceholder extends StatelessWidget {
  const _AnalyzeShotPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AnalyzeShotHero._height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.sports_basketball_rounded,
            size: 96,
            color: PremiumColors.accentOrange.withValues(alpha: 0.85),
          ),
          Positioned(
            left: 48,
            top: 52,
            child: Icon(
              Icons.timeline_rounded,
              size: 36,
              color: PremiumColors.accentOrange.withValues(alpha: 0.4),
            ),
          ),
          Positioned(
            right: 56,
            top: 64,
            child: Icon(
              Icons.bubble_chart_outlined,
              size: 32,
              color: PremiumColors.accentOrange.withValues(alpha: 0.35),
            ),
          ),
          Positioned(
            right: 44,
            bottom: 48,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: PremiumColors.cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.videocam_rounded,
                color: PremiumColors.accentOrange,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
