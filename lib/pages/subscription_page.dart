import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/subscription_plan.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/subscription_service.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';
import 'package:shootiq/widgets/subscription/subscription_widgets.dart';

class _FeatureItem {
  const _FeatureItem({
    required this.emoji,
    required this.title,
    required this.description,
  });

  final String emoji;
  final String title;
  final String description;
}

const _features = [
  _FeatureItem(
    emoji: '✓',
    title: 'Unlimited AI Shot Analysis',
    description: 'Record or upload every practice take.',
  ),
  _FeatureItem(
    emoji: '✓',
    title: 'AI Shooting Coach',
    description: 'Get form cues tailored to your shot.',
  ),
  _FeatureItem(
    emoji: '✓',
    title: 'Movement Breakdown',
    description: 'See elbow, balance, release, and more.',
  ),
  _FeatureItem(
    emoji: '✓',
    title: 'Shot History',
    description: 'Keep every analyzed session in one place.',
  ),
  _FeatureItem(
    emoji: '✓',
    title: 'Progress Tracking',
    description: 'Watch your shooting score improve.',
  ),
];

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key, this.nextRoute});

  /// Optional destination after a successful subscribe (e.g. `/camera`).
  final String? nextRoute;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  /// Yearly is the default recommended plan.
  int _selectedIndex = 0;
  bool _isProcessing = false;
  bool _checkingAccess = true;
  bool _isManaging = false;
  String _statusLabel = 'Free';

  SubscriptionPlan get _selectedPlan => SubscriptionPlans.all[_selectedIndex];

  String get _ctaLabel {
    if (_isManaging) return 'Update Plan';
    return _selectedPlan.includesTrial
        ? 'Start 3-Day Free Trial'
        : 'Continue';
  }

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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final allowed = await SubscriptionService.hasActiveSubscription();
    if (!mounted) return;

    // Paywall return path only: already subscribed → continue to destination.
    // Manage Subscription opens this page without `next` and must stay open.
    final next = widget.nextRoute;
    if (allowed && next != null && next.isNotEmpty) {
      context.go(next);
      return;
    }

    var selectedIndex = 0;
    var statusLabel = 'Free';
    if (allowed) {
      final plan = await SubscriptionService.currentPlan();
      statusLabel = await SubscriptionService.statusLabel();
      if (plan != null) {
        final index = SubscriptionPlans.all.indexWhere((p) => p.id == plan.id);
        if (index >= 0) selectedIndex = index;
      }
    }

    if (!mounted) return;
    setState(() {
      _isManaging = allowed;
      _selectedIndex = selectedIndex;
      _statusLabel = statusLabel;
      _checkingAccess = false;
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await SubscriptionService.purchasePlan(_selectedPlan);
      if (!mounted) return;

      final nextRoute = widget.nextRoute;
      if (nextRoute != null && nextRoute.isNotEmpty) {
        context.go(nextRoute);
        return;
      }

      if (_isManaging) {
        final label = await SubscriptionService.statusLabel();
        if (!mounted) return;
        setState(() => _statusLabel = label);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plan updated to ${_selectedPlan.title}.'),
          ),
        );
        return;
      }

      if (context.canPop()) {
        context.pop();
        return;
      }
      context.go(AppRoutes.dashboard);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _onCancelSubscription() async {
    if (_isProcessing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: const Text(
          'You’ll lose ShootIQ Pro access immediately. '
          'You can resubscribe anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Plan'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel Plan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      await SubscriptionService.clearSubscription();
      if (!mounted) return;
      setState(() {
        _isManaging = false;
        _statusLabel = 'Free';
        _selectedIndex = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscription canceled.')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(
        backgroundColor: PremiumColors.white,
        body: Center(
          child: CircularProgressIndicator(color: ShootIQTheme.primaryBlue),
        ),
      );
    }

    return Scaffold(
      backgroundColor: PremiumColors.white,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  PremiumSpacing.horizontal,
                  8,
                  PremiumSpacing.horizontal,
                  0,
                ),
                child: CustomBackButton(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    PremiumSpacing.horizontal,
                    16,
                    PremiumSpacing.horizontal,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeaderSection(isManaging: _isManaging),
                      if (_isManaging) ...[
                        const SizedBox(height: 16),
                        _CurrentPlanBanner(statusLabel: _statusLabel),
                      ],
                      const SizedBox(height: PremiumSpacing.section),
                      const _FeatureSection(),
                      const SizedBox(height: PremiumSpacing.section),
                      _PlanSection(
                        selectedIndex: _selectedIndex,
                        enabled: !_isProcessing,
                        onSelected: (index) {
                          setState(() => _selectedIndex = index);
                        },
                      ),
                      const SizedBox(height: 28),
                      _ContinueButton(
                        isProcessing: _isProcessing,
                        label: _ctaLabel,
                        onPressed: _onContinue,
                      ),
                      if (_isManaging) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 52,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed:
                                _isProcessing ? null : _onCancelSubscription,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ShootIQTheme.redAccent,
                              side: const BorderSide(
                                color: ShootIQTheme.redBorder,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('Cancel Subscription'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      OnboardingFootnote(
                        text: _isManaging
                            ? 'You’re managing your ShootIQ Pro plan.\nSwitch plans anytime or cancel below.'
                            : _selectedPlan.includesTrial
                                ? 'No charge today. After 3 days, \$59.99/year.\nCancel anytime before the trial ends.'
                                : 'Billed ${_selectedPlan.priceLabel.toLowerCase()}.\nCancel anytime. Renews automatically unless cancelled.',
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

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.isManaging});

  final bool isManaging;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          isManaging ? 'Manage Subscription' : 'ShootIQ Pro',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: ShootIQTheme.textPrimary,
                height: 1.15,
                letterSpacing: -0.7,
              ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            isManaging
                ? 'View your plan, switch billing, or cancel anytime.'
                : 'Unlock your AI basketball trainer.',
            textAlign: TextAlign.center,
            style: const TextStyle(
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

class _CurrentPlanBanner extends StatelessWidget {
  const _CurrentPlanBanner({required this.statusLabel});

  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShootIQTheme.primaryBlue.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_rounded,
            color: ShootIQTheme.primaryBlue,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Current: $statusLabel',
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _features.length; i++) ...[
          if (i > 0) const SizedBox(height: PremiumSpacing.cardGap),
          SubscriptionFeatureCard(
            emoji: _features[i].emoji,
            title: _features[i].title,
            description: _features[i].description,
          ),
        ],
      ],
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.selectedIndex,
    required this.enabled,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < SubscriptionPlans.all.length; i++) ...[
          if (i > 0) const SizedBox(height: PremiumSpacing.goalCardGap),
          SubscriptionPlanCard(
            title: SubscriptionPlans.all[i].title,
            price: SubscriptionPlans.all[i].includesTrial
                ? (SubscriptionPlans.all[i].trialLabel ??
                    SubscriptionPlans.all[i].priceLabel)
                : SubscriptionPlans.all[i].priceLabel,
            secondaryPrice: SubscriptionPlans.all[i].includesTrial
                ? SubscriptionPlans.all[i].afterTrialLabel
                : SubscriptionPlans.all[i].subtitle,
            badge: SubscriptionPlans.all[i].badge,
            isSelected: selectedIndex == i,
            highlighted: SubscriptionPlans.all[i].isYearly,
            features: SubscriptionPlans.all[i].isYearly
                ? SubscriptionPlans.all[i].highlightFeatures
                : const [],
            onTap: enabled ? () => onSelected(i) : () {},
          ),
        ],
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.isProcessing,
    required this.onPressed,
    required this.label,
  });

  final bool isProcessing;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      width: double.infinity,
      child: FilledButton(
        onPressed: isProcessing ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: ShootIQTheme.buttonBlue,
          disabledBackgroundColor:
              ShootIQTheme.buttonBlue.withValues(alpha: 0.7),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        child: isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(label),
      ),
    );
  }
}
