import 'package:flutter/material.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

/// Hero illustration for the first-shot upload onboarding screen.
class ShotUploadHero extends StatelessWidget {
  const ShotUploadHero({super.key});

  static const _assetPath = 'assets/images/upload_shot.png';
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

class _ShotUploadPlaceholder extends StatelessWidget {
  const _ShotUploadPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ShotUploadHero._height,
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
            size: 88,
            color: PremiumColors.accentOrange.withValues(alpha: 0.8),
          ),
          Positioned(
            right: 48,
            bottom: 44,
            child: Container(
              width: 56,
              height: 56,
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

/// Selectable source card with emoji, copy, and action button.
class ShotSourceCard extends StatelessWidget {
  const ShotSourceCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.isSelected,
    required this.onSelect,
    required this.onAction,
  });

  final String emoji;
  final String title;
  final String description;
  final String buttonLabel;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSelected ? PremiumColors.selectedOrangeBg : PremiumColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? PremiumColors.accentOrange
              : PremiumColors.cardBorder,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 28, height: 1)),
                    const SizedBox(width: 12),
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
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: PremiumColors.subtitle,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: isSelected ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedScale(
                        scale: isSelected ? 1 : 0.75,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutBack,
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: PremiumColors.accentOrange,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () {
                      onSelect();
                      onAction();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PremiumColors.accentOrange,
                      side: const BorderSide(color: PremiumColors.accentOrange),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
