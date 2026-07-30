import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

/// Emoji feature row used on the subscription paywall.
class SubscriptionFeatureCard extends StatelessWidget {
  const SubscriptionFeatureCard({
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PremiumColors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PremiumColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22, height: 1.2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: PremiumColors.title,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: PremiumColors.subtitle,
                    height: 1.35,
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

/// Selectable subscription plan card with animated selected state.
class SubscriptionPlanCard extends StatelessWidget {
  const SubscriptionPlanCard({
    super.key,
    required this.title,
    required this.price,
    required this.isSelected,
    required this.onTap,
    this.badge,
    this.secondaryPrice,
    this.highlighted = false,
    this.features = const [],
  });

  final String title;
  final String price;
  final String? secondaryPrice;
  final String? badge;
  final bool isSelected;
  final bool highlighted;
  final List<String> features;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isSelected
            ? ShootIQTheme.primaryBlue.withValues(alpha: 0.06)
            : PremiumColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? (highlighted ? ShootIQTheme.redBorder : PremiumColors.accentOrange)
              : PremiumColors.cardBorder,
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected && highlighted ? ShootIQTheme.cardShadow : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (badge != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: ShootIQTheme.primaryBlue,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: ShootIQTheme.redBorder,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: PremiumColors.title,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            price,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: highlighted
                                  ? ShootIQTheme.primaryBlue
                                  : PremiumColors.title,
                              height: 1.2,
                            ),
                          ),
                          if (secondaryPrice != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              secondaryPrice!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: PremiumColors.subtitle,
                                height: 1.2,
                              ),
                            ),
                          ],
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
                          color: ShootIQTheme.primaryBlue,
                          size: 26,
                        ),
                      ),
                    ),
                  ],
                ),
                if (features.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: PremiumColors.cardBorder),
                  const SizedBox(height: 10),
                  for (final feature in features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: ShootIQTheme.primaryBlue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: PremiumColors.title,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
