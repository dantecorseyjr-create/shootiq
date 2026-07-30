/// ShootIQ Pro billing plans (local + future StoreKit / Play Billing IDs).
enum SubscriptionPlanId {
  weekly,
  monthly,
  yearly,
}

/// Catalog entry for the premium paywall.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.title,
    required this.priceLabel,
    required this.productId,
    this.badge,
    this.trialLabel,
    this.afterTrialLabel,
    this.subtitle,
    this.includesTrial = false,
    this.trialDays = 0,
    this.highlightFeatures = const [],
  });

  final SubscriptionPlanId id;
  final String title;
  final String priceLabel;
  final String productId;
  final String? badge;
  final String? trialLabel;
  final String? afterTrialLabel;
  final String? subtitle;
  final bool includesTrial;
  final int trialDays;
  final List<String> highlightFeatures;

  bool get isYearly => id == SubscriptionPlanId.yearly;
}

/// Canonical ShootIQ Pro plans.
abstract final class SubscriptionPlans {
  static const yearlyFeatures = [
    '3-day free trial',
    'Unlimited AI shot analysis',
    'AI shooting coach',
    'Movement breakdown',
    'Shot history',
    'Progress tracking',
  ];

  static const sharedFeatures = [
    'Unlimited AI Shot Analysis',
    'AI Shooting Coach',
    'Movement Breakdown',
    'Shot History',
    'Progress Tracking',
  ];

  /// Display order: Yearly (recommended) → Monthly → Weekly.
  static const List<SubscriptionPlan> all = [
    yearly,
    monthly,
    weekly,
  ];

  static const yearly = SubscriptionPlan(
    id: SubscriptionPlanId.yearly,
    title: 'Yearly',
    priceLabel: '\$59.99/year',
    productId: 'shootiq_pro_yearly',
    badge: 'BEST VALUE',
    trialLabel: '3-Day Free Trial',
    afterTrialLabel: '\$59.99/year after trial',
    includesTrial: true,
    trialDays: 3,
    highlightFeatures: yearlyFeatures,
  );

  static const monthly = SubscriptionPlan(
    id: SubscriptionPlanId.monthly,
    title: 'Monthly',
    priceLabel: '\$14.99/month',
    productId: 'shootiq_pro_monthly',
    subtitle: 'Billed monthly · No free trial',
  );

  static const weekly = SubscriptionPlan(
    id: SubscriptionPlanId.weekly,
    title: 'Weekly',
    priceLabel: '\$4.99/week',
    productId: 'shootiq_pro_weekly',
    subtitle: 'Billed weekly · No free trial',
  );

  static SubscriptionPlan byId(SubscriptionPlanId id) {
    return switch (id) {
      SubscriptionPlanId.yearly => yearly,
      SubscriptionPlanId.monthly => monthly,
      SubscriptionPlanId.weekly => weekly,
    };
  }

  static SubscriptionPlan? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final plan in all) {
      if (plan.id.name == raw || plan.productId == raw) return plan;
    }
    return null;
  }
}
