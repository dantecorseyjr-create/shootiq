import 'package:flutter/material.dart';

/// Design tokens for onboarding / light surfaces (white, blue, red).
abstract final class PremiumColors {
  static const white = Color(0xFFFFFFFF);
  static const title = Color(0xFF111827);
  static const subtitle = Color(0xFF6B7280);
  static const cardBackground = Color(0xFFFFFFFF);
  static const cardBorder = Color(0xFFE5E7EB);
  static const orange = Color(0xFF0057FF); // primary blue (legacy name)
  static const accentOrange = Color(0xFF0066FF); // button blue (legacy name)
  static const selectedOrangeBg = Color(0xFFEFF4FF); // light blue tint
  static const redAccent = Color(0xFFFF2D2D);
  static const redBorder = Color(0xFFE60000);
  static const checkGreen = Color(0xFF22C55E);
  static const placeholder = Color(0xFFF3F4F6);
  static const disclaimer = Color(0xFF9CA3AF);
}

/// Shared spacing for the premium onboarding screen.
abstract final class PremiumSpacing {
  static const horizontal = 24.0;
  static const heroToTitle = 32.0;
  static const section = 24.0;
  static const cardGap = 12.0;
  static const goalCardGap = 16.0;
}

/// Rounded feature card with orange icon, title, and description.
class PremiumFeatureCard extends StatelessWidget {
  const PremiumFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PremiumColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: PremiumColors.orange,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: PremiumColors.title,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: PremiumColors.subtitle,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero image with fallback placeholder when the asset is missing.
class PremiumHeroImage extends StatelessWidget {
  const PremiumHeroImage({super.key});

  static const _assetPath = 'assets/images/premium.png';

  @override
  Widget build(BuildContext context) {
    return const OnboardingIllustration(
      assetPath: _assetPath,
      fallbackIcon: Icons.sports_basketball,
    );
  }
}

/// Configurable onboarding illustration with rounded placeholder fallback.
class OnboardingIllustration extends StatelessWidget {
  const OnboardingIllustration({
    super.key,
    required this.assetPath,
    required this.fallbackIcon,
    this.placeholderColor,
  });

  final String assetPath;
  final IconData fallbackIcon;
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final fallbackColor = placeholderColor ?? PremiumColors.placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        assetPath,
        height: 280,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          height: 280,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: fallbackColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fallbackIcon,
                  size: 48,
                  color: PremiumColors.cardBorder,
                ),
                const SizedBox(height: 12),
                Text(
                  'Image failed: $error\n$assetPath',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PremiumColors.subtitle,
                    height: 1.35,
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

/// Centered title and subtitle matching onboarding typography.
class OnboardingTitleSection extends StatelessWidget {
  const OnboardingTitleSection({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: PremiumColors.title,
                height: 1.15,
                letterSpacing: -0.8,
              ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: PremiumColors.subtitle,
                  height: 1.45,
                ),
          ),
        ),
      ],
    );
  }
}

/// Full-width primary button for onboarding screens (blue + red border).
class OnboardingPrimaryButton extends StatelessWidget {
  const OnboardingPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final color = backgroundColor ?? PremiumColors.accentOrange;

    return SizedBox(
      height: 58,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          elevation: 0,
          side: const BorderSide(color: PremiumColors.redBorder, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Selectable goal option card for onboarding goal selection.
class GoalOptionCard extends StatelessWidget {
  const GoalOptionCard({
    super.key,
    required this.emoji,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
    this.height = 78,
  });

  final String emoji;
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      constraints: BoxConstraints(minHeight: height),
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 24, height: 1)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: PremiumColors.title,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: PremiumColors.subtitle,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
          ),
        ),
      ),
    );
  }
}

/// Green check row for feature lists.
class OnboardingCheckRow extends StatelessWidget {
  const OnboardingCheckRow({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: PremiumColors.checkGreen,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: PremiumColors.title,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small centered footnote text.
class OnboardingFootnote extends StatelessWidget {
  const OnboardingFootnote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: PremiumColors.disclaimer,
            height: 1.5,
          ),
    );
  }
}

/// Premium rounded surface card for onboarding content blocks.
class OnboardingSurfaceCard extends StatelessWidget {
  const OnboardingSurfaceCard({
    super.key,
    required this.child,
    this.borderRadius = 22,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: PremiumColors.cardBorder),
      ),
      child: child,
    );
  }
}

/// Metric row with emoji label, orange progress bar, and percentage.
class AnalysisMetricRow extends StatelessWidget {
  const AnalysisMetricRow({
    super.key,
    required this.emoji,
    required this.label,
    required this.percent,
  });

  final String emoji;
  final String label;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16, height: 1)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: PremiumColors.title,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PremiumColors.accentOrange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: PremiumColors.cardBorder,
              color: PremiumColors.accentOrange,
            ),
        ),
      ],
    );
  }
}

/// AI coach tip card with psychology icon and coaching message.
class AiCoachTipCard extends StatelessWidget {
  const AiCoachTipCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return OnboardingSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: PremiumColors.accentOrange,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.psychology_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Coach',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PremiumColors.title,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
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

/// Five-star rating row with caption.
class PremiumRatingSection extends StatelessWidget {
  const PremiumRatingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            5,
            (_) => const Icon(
              Icons.star_rounded,
              color: PremiumColors.orange,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '4.9 Rating • Thousands of Players',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: PremiumColors.subtitle,
          ),
        ),
      ],
    );
  }
}

/// Pricing headline and subline (yearly trial offer).
class PremiumPricingSection extends StatelessWidget {
  const PremiumPricingSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          '3-Day Free Trial',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: PremiumColors.title,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Then \$59.99/year · Best Value',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: PremiumColors.subtitle,
          ),
        ),
      ],
    );
  }
}
