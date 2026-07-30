import 'package:flutter/material.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

/// Subtle elevation shadow for dashboard cards.
abstract final class ImproveShadows {
  static List<BoxShadow> get card => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

/// Dashboard page header with title and subtitle.
class ImproveHeader extends StatelessWidget {
  const ImproveHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Improve Your Shot',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: PremiumColors.title,
                height: 1.15,
                letterSpacing: -0.6,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Build a better jumper with AI feedback, instant replay, and practice tools.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: PremiumColors.subtitle,
                height: 1.45,
              ),
        ),
      ],
    );
  }
}

/// Large score summary card with circular progress ring.
class ShotScoreCard extends StatelessWidget {
  const ShotScoreCard({
    super.key,
    this.score = 87,
    this.monthlyChange = '+5 this month 📈',
    this.progress = 0.87,
  });

  final int score;
  final String monthlyChange;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: PremiumColors.cardBorder),
        boxShadow: ImproveShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Current Shot Score',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: PremiumColors.subtitle,
                  ),
                ),
                const SizedBox(height: 6),
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
                const SizedBox(height: 8),
                Text(
                  monthlyChange,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: PremiumColors.accentOrange,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: PremiumColors.cardBorder,
                    color: PremiumColors.accentOrange,
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: PremiumColors.title,
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

/// Large feature card with icon, copy, and action link.
class ImproveFeatureCard extends StatelessWidget {
  const ImproveFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PremiumColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PremiumColors.cardBorder),
        boxShadow: ImproveShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: PremiumColors.selectedOrangeBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: PremiumColors.accentOrange, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: PremiumColors.title,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: PremiumColors.subtitle,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: PremiumColors.accentOrange,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

/// Compact training tile for side-by-side grid.
class TrainingMiniCard extends StatelessWidget {
  const TrainingMiniCard({
    super.key,
    required this.emoji,
    required this.label,
    required this.title,
    this.onTap,
  });

  final String emoji;
  final String label;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PremiumColors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: PremiumColors.cardBorder),
            boxShadow: ImproveShadows.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28, height: 1)),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: PremiumColors.subtitle,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: PremiumColors.title,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom navigation bar for the main app shell (Improve tab only for now).
class ImproveBottomNav extends StatelessWidget {
  const ImproveBottomNav({super.key, this.activeIndex = 0});

  final int activeIndex;

  static const _items = [
    (icon: Icons.sports_basketball, label: 'Improve'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PremiumColors.white,
        border: const Border(
          top: BorderSide(color: PremiumColors.cardBorder),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _items.length; i++)
                _NavItem(
                  icon: _items[i].icon,
                  label: _items[i].label,
                  isActive: i == activeIndex,
                  isEnabled: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isEnabled,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? PremiumColors.accentOrange : PremiumColors.disclaimer;

    return IgnorePointer(
      ignoring: !isEnabled,
      child: Opacity(
        opacity: isEnabled ? 1 : 0.45,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section heading for dashboard groups.
class ImproveSectionTitle extends StatelessWidget {
  const ImproveSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: PremiumColors.title,
        letterSpacing: -0.3,
      ),
    );
  }
}
