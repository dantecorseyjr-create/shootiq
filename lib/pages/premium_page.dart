import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/subscription_plan.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/subscription_service.dart';

/// ShootIQ Pro paywall — shown when free users try to analyze a shot.
class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  /// Yearly is the default recommended plan.
  int _selectedIndex = 0;
  bool _isProcessing = false;
  bool _checkingAccess = true;

  String get _nextRoute {
    final next = GoRouterState.of(context).uri.queryParameters['next'];
    if (next != null && next.isNotEmpty) return next;
    return SubscriptionService.defaultAnalysisRoute;
  }

  SubscriptionPlan get _selectedPlan => SubscriptionPlans.all[_selectedIndex];

  String get _ctaLabel => _selectedPlan.includesTrial
      ? 'Start 3-Day Free Trial'
      : 'Continue';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
    _skipIfAlreadySubscribed();
  }

  Future<void> _skipIfAlreadySubscribed() async {
    final allowed = await SubscriptionService.hasActiveSubscription();
    if (!mounted) return;
    if (allowed) {
      context.go(_nextRoute);
      return;
    }
    setState(() => _checkingAccess = false);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _activateAndContinue() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await SubscriptionService.purchasePlan(_selectedPlan);
      if (!mounted) return;
      context.go(_nextRoute);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(
        backgroundColor: ShootIQTheme.background,
        body: Center(
          child: CircularProgressIndicator(color: ShootIQTheme.primaryBlue),
        ),
      );
    }

    return Scaffold(
      backgroundColor: ShootIQTheme.background,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.dashboard);
                        }
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: ShootIQTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _isProcessing
                          ? null
                          : () => context.push(
                                '${AppRoutes.subscription}?next=${Uri.encodeComponent(_nextRoute)}',
                              ),
                      child: const Text(
                        'All Plans',
                        style: TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: ShootIQTheme.cardBackground,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: ShootIQTheme.cardBorder),
                          boxShadow: ShootIQTheme.cardShadow,
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'ShootIQ Pro',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ShootIQTheme.textPrimary,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Unlock your AI basketball trainer.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: ShootIQTheme.textSecondary,
                                fontSize: 16,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'What\'s included',
                        style: TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final feature
                          in SubscriptionPlans.sharedFeatures) ...[
                        _FeatureRow(label: feature),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 18),
                      const Text(
                        'Choose your plan',
                        style: TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0;
                          i < SubscriptionPlans.all.length;
                          i++) ...[
                        _PlanCard(
                          plan: SubscriptionPlans.all[i],
                          selected: _selectedIndex == i,
                          onTap: _isProcessing
                              ? null
                              : () => setState(() => _selectedIndex = i),
                        ),
                        if (i < SubscriptionPlans.all.length - 1)
                          const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed:
                              _isProcessing ? null : _activateAndContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: ShootIQTheme.buttonBlue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: ShootIQTheme.buttonBlue
                                .withValues(alpha: 0.7),
                            side: const BorderSide(
                              color: ShootIQTheme.redBorder,
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(_ctaLabel),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedPlan.includesTrial
                            ? 'No charge today. After 3 days, \$59.99/year. Cancel anytime.'
                            : 'Billed ${_selectedPlan.priceLabel.toLowerCase()}. Cancel anytime.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: ShootIQTheme.primaryBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: ShootIQTheme.primaryBlue,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: ShootIQTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final SubscriptionPlan plan;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isYearly = plan.isYearly;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? ShootIQTheme.primaryBlue.withValues(alpha: 0.06)
                : ShootIQTheme.cardBackground,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? (isYearly
                      ? ShootIQTheme.redBorder
                      : ShootIQTheme.primaryBlue)
                  : ShootIQTheme.cardBorder,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected && isYearly ? ShootIQTheme.cardShadow : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              plan.title,
                              style: const TextStyle(
                                color: ShootIQTheme.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (plan.badge != null) ...[
                              const SizedBox(width: 8),
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
                                  plan.badge!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (plan.trialLabel != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            plan.trialLabel!,
                            style: const TextStyle(
                              color: ShootIQTheme.primaryBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          plan.afterTrialLabel ?? plan.priceLabel,
                          style: const TextStyle(
                            color: ShootIQTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (plan.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            plan.subtitle!,
                            style: const TextStyle(
                              color: ShootIQTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected
                        ? ShootIQTheme.primaryBlue
                        : ShootIQTheme.textSecondary,
                  ),
                ],
              ),
              if (isYearly && plan.highlightFeatures.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1, color: ShootIQTheme.cardBorder),
                const SizedBox(height: 12),
                for (final feature in plan.highlightFeatures) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
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
                              color: ShootIQTheme.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
