import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/subscription_plan.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/subscription_service.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class ManageSubscriptionPage extends StatefulWidget {
  const ManageSubscriptionPage({super.key});

  @override
  State<ManageSubscriptionPage> createState() => _ManageSubscriptionPageState();
}

class _ManageSubscriptionPageState extends State<ManageSubscriptionPage> {
  bool _loading = true;
  String _status = SubscriptionService.statusNone;
  String _label = 'Free';
  SubscriptionPlan? _plan;
  DateTime? _trialEnds;
  DateTime? _expires;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await SubscriptionService.subscriptionStatus();
    final label = await SubscriptionService.statusLabel();
    final plan = await SubscriptionService.currentPlan();
    final trialEnds = await SubscriptionService.trialEndsAt();
    final expires = await SubscriptionService.expiresAt();
    if (!mounted) return;
    setState(() {
      _status = status;
      _label = label;
      _plan = plan;
      _trialEnds = trialEnds;
      _expires = expires;
      _loading = false;
    });
  }

  String _fmt(DateTime? value) {
    if (value == null) return '—';
    return DateFormat.yMMMMd().add_jm().format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final inTrial = _status == SubscriptionService.statusTrial;
    final active = _status == SubscriptionService.statusActive || inTrial;

    return SettingsSubpageScaffold(
      title: 'Manage Subscription',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                SettingsInfoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active ? 'ShootIQ Pro' : 'Free plan',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: ShootIQTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _row('Current plan', _plan?.title ?? (active ? _label : 'Free')),
                      _row('Status', _label),
                      _row(
                        'Trial status',
                        inTrial
                            ? 'Active · ends ${_fmt(_trialEnds)}'
                            : (_plan?.includesTrial == true && !active
                                ? '3-day free trial available on Yearly'
                                : 'Not in trial'),
                      ),
                      _row(
                        'Renewal date',
                        inTrial
                            ? 'Converts after trial (${_fmt(_trialEnds)})'
                            : _fmt(_expires),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SettingsPrimaryButton(
                  label: 'Manage Subscription',
                  onPressed: () => context.push(AppRoutes.subscription),
                ),
                const SizedBox(height: 12),
                SettingsOutlinedButton(
                  label: 'Restore Purchases',
                  onPressed: () => context.push(AppRoutes.restorePurchases),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Subscriptions renew automatically unless cancelled in your store account settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
