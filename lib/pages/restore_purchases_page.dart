import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/services/subscription_service.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class RestorePurchasesPage extends StatefulWidget {
  const RestorePurchasesPage({super.key});

  @override
  State<RestorePurchasesPage> createState() => _RestorePurchasesPageState();
}

class _RestorePurchasesPageState extends State<RestorePurchasesPage> {
  bool _busy = false;
  String? _result;

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      // TODO(iap): Wire StoreKit / Play Billing restore via `in_app_purchase`.
      // 1) Query past purchases
      // 2) Validate receipts with store / backend
      // 3) Call SubscriptionService.setSubscriptionStatus(...)
      final restored = await SubscriptionService.restorePurchases();
      if (!mounted) return;
      setState(() {
        _result = restored
            ? 'Purchases restored. Your ShootIQ Pro access is active.'
            : 'No active subscription found to restore on this device yet.';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_result!)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = 'Restore failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_result!)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Restore Purchases',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          SettingsInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Already subscribed?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: ShootIQTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Restore Purchases recovers an existing Apple or Google subscription after reinstalling ShootIQ or signing in on a new device.',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Debug builds use a simulated restore against local entitlement state until StoreKit is connected.',
                    style: TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          SettingsPrimaryButton(
            label: 'Restore Purchases',
            isLoading: _busy,
            onPressed: _restore,
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            SettingsInfoCard(
              child: Text(
                _result!,
                style: const TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
