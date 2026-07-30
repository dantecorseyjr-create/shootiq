import 'package:flutter/material.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

/// Hero illustration for the camera setup onboarding screen.
class CameraSetupHero extends StatelessWidget {
  const CameraSetupHero({super.key});

  static const _assetPath = 'assets/images/camera_setup.png';
  static const _height = 260.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        _assetPath,
        height: _height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
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
    );
  }
}

class _CameraSetupPlaceholder extends StatelessWidget {
  const _CameraSetupPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: CameraSetupHero._height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 36,
            bottom: 40,
            child: Icon(
              Icons.sports_basketball_rounded,
              size: 72,
              color: PremiumColors.accentOrange.withValues(alpha: 0.85),
            ),
          ),
          Positioned(
            right: 40,
            top: 48,
            child: Container(
              width: 64,
              height: 108,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: PremiumColors.cardBorder, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam_rounded,
                    size: 28,
                    color: PremiumColors.accentOrange,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: PremiumColors.accentOrange,
                        width: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 72,
            top: 56,
            child: Icon(
              Icons.timeline_rounded,
              size: 36,
              color: PremiumColors.accentOrange.withValues(alpha: 0.45),
            ),
          ),
          Positioned(
            right: 120,
            bottom: 72,
            child: Icon(
              Icons.bubble_chart_outlined,
              size: 30,
              color: PremiumColors.accentOrange.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact emoji benefit row for permission / feature lists.
class PermissionBenefitRow extends StatelessWidget {
  const PermissionBenefitRow({
    super.key,
    required this.emoji,
    required this.label,
  });

  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22, height: 1)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PremiumColors.title,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
