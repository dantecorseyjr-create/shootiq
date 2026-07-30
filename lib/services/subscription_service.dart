import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shootiq/models/subscription_plan.dart';

/// Local subscription entitlement for gating real shot analysis (camera/upload).
///
/// Free users can explore Home, Profile, Progress, AI Coach, History, and
/// Settings. Only camera capture / video upload analysis requires an active plan
/// or an unexpired free trial.
///
/// Checkout is currently simulated — replace [_simulateStorePurchase] with
/// StoreKit / Play Billing when product IDs are configured.
class SubscriptionService {
  SubscriptionService._();

  static const _statusKey = 'shootiq_subscription_status';
  static const _subscribedKey = 'shootiq_is_subscribed'; // legacy bool
  static const _planKey = 'shootiq_subscription_plan';
  static const _trialEndsAtKey = 'shootiq_trial_ends_at';
  static const _expiresAtKey = 'shootiq_subscription_expires_at';

  static const statusNone = 'none';
  static const statusActive = 'active';
  static const statusTrial = 'trial';

  /// Default destination after a successful subscribe from the analyze paywall.
  static const defaultAnalysisRoute = '/camera';
  static const premiumRoute = '/premium';

  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Current subscription status (`none`, `trial`, or `active`).
  ///
  /// Expired trials / subscriptions are cleared back to `none`.
  static Future<String> subscriptionStatus() async {
    final prefs = await _ensurePrefs();
    var status = prefs.getString(_statusKey);

    // Migrate legacy boolean flag.
    if (status == null ||
        (status != statusActive &&
            status != statusNone &&
            status != statusTrial)) {
      final legacy = prefs.getBool(_subscribedKey) ?? false;
      status = legacy ? statusActive : statusNone;
      await prefs.setString(_statusKey, status);
    }

    if (status == statusTrial) {
      final endsAt = await trialEndsAt();
      if (endsAt == null || !DateTime.now().toUtc().isBefore(endsAt)) {
        // Trial ended → convert to paid yearly active (simulated renewal),
        // or expire if we cannot confirm. For local simulation we promote
        // yearly trial completions to active so access continues after trial.
        final plan = await currentPlan();
        if (plan?.isYearly == true) {
          // Simulated post-trial charge: convert to paid yearly.
          await setSubscriptionStatus(
            statusActive,
            planId: SubscriptionPlanId.yearly,
            expiresAt: DateTime.now().toUtc().add(const Duration(days: 365)),
          );
          return statusActive;
        }
        await clearSubscription();
        return statusNone;
      }
    }

    if (status == statusActive) {
      final expires = await expiresAt();
      if (expires != null && !DateTime.now().toUtc().isBefore(expires)) {
        await clearSubscription();
        return statusNone;
      }
    }

    return status;
  }

  /// Whether the user has premium access (active paid plan **or** unexpired trial).
  static Future<bool> hasActiveSubscription() async {
    final status = await subscriptionStatus();
    return status == statusActive || status == statusTrial;
  }

  /// Whether the user is currently in a free trial window.
  static Future<bool> isInTrial() async {
    return (await subscriptionStatus()) == statusTrial;
  }

  static Future<DateTime?> trialEndsAt() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(_trialEndsAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  static Future<DateTime?> expiresAt() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(_expiresAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  static Future<SubscriptionPlan?> currentPlan() async {
    final prefs = await _ensurePrefs();
    return SubscriptionPlans.tryParse(prefs.getString(_planKey));
  }

  /// Persist subscription status after a successful purchase / trial start.
  static Future<void> setSubscribed(bool value) async {
    if (value) {
      await setSubscriptionStatus(statusActive);
    } else {
      await clearSubscription();
    }
  }

  /// Set raw status string and optional plan metadata.
  static Future<void> setSubscriptionStatus(
    String status, {
    SubscriptionPlanId? planId,
    DateTime? trialEndsAt,
    DateTime? expiresAt,
  }) async {
    final prefs = await _ensurePrefs();
    final normalized = switch (status) {
      statusActive => statusActive,
      statusTrial => statusTrial,
      _ => statusNone,
    };

    await prefs.setString(_statusKey, normalized);
    await prefs.setBool(
      _subscribedKey,
      normalized == statusActive || normalized == statusTrial,
    );

    if (planId != null) {
      await prefs.setString(_planKey, planId.name);
    } else if (normalized == statusNone) {
      await prefs.remove(_planKey);
    }

    if (trialEndsAt != null) {
      await prefs.setString(
        _trialEndsAtKey,
        trialEndsAt.toUtc().toIso8601String(),
      );
    } else if (normalized != statusTrial) {
      await prefs.remove(_trialEndsAtKey);
    }

    if (expiresAt != null) {
      await prefs.setString(
        _expiresAtKey,
        expiresAt.toUtc().toIso8601String(),
      );
    } else if (normalized == statusNone) {
      await prefs.remove(_expiresAtKey);
    }
  }

  static Future<void> clearSubscription() async {
    final prefs = await _ensurePrefs();
    await prefs.setString(_statusKey, statusNone);
    await prefs.setBool(_subscribedKey, false);
    await prefs.remove(_planKey);
    await prefs.remove(_trialEndsAtKey);
    await prefs.remove(_expiresAtKey);
  }

  /// Starts the (simulated) Apple/Google purchase for [plan].
  ///
  /// - Yearly: 3-day free trial, then $59.99/year (no charge during trial).
  /// - Monthly: $14.99 charged immediately.
  /// - Weekly: $4.99 charged immediately.
  static Future<void> purchasePlan(SubscriptionPlan plan) async {
    await _simulateStorePurchase(plan);

    if (plan.includesTrial && plan.trialDays > 0) {
      final ends = DateTime.now().toUtc().add(Duration(days: plan.trialDays));
      await setSubscriptionStatus(
        statusTrial,
        planId: plan.id,
        trialEndsAt: ends,
      );
      return;
    }

    final expires = DateTime.now().toUtc().add(
          switch (plan.id) {
            SubscriptionPlanId.weekly => const Duration(days: 7),
            SubscriptionPlanId.monthly => const Duration(days: 30),
            SubscriptionPlanId.yearly => const Duration(days: 365),
          },
        );

    await setSubscriptionStatus(
      statusActive,
      planId: plan.id,
      expiresAt: expires,
    );
  }

  /// Placeholder for StoreKit / Play Billing. Keeps UX snappy for now.
  static Future<void> _simulateStorePurchase(SubscriptionPlan plan) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    // When wiring real IAP, purchase [plan.productId] here.
    // Yearly products should be configured with a 3-day introductory offer.
    assert(plan.productId.isNotEmpty);
  }

  /// Human-readable status for Settings / Profile.
  static Future<String> statusLabel() async {
    final status = await subscriptionStatus();
    final plan = await currentPlan();
    return switch (status) {
      statusTrial => plan == null
          ? 'Free Trial'
          : 'Free Trial · ${plan.title}',
      statusActive => plan == null ? 'ShootIQ Pro' : 'ShootIQ Pro · ${plan.title}',
      _ => 'Free',
    };
  }

  /// Restores store entitlements.
  ///
  /// TODO(iap): Replace with StoreKit / Play Billing purchase restoration.
  /// Current behavior reloads local entitlement state for development builds.
  static Future<bool> restorePurchases() async {
    // Simulated restore latency.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final status = await subscriptionStatus();
    return status == statusActive || status == statusTrial;
  }

  /// Reusable access check for real shot analysis (camera / upload).
  static Future<bool> checkAnalysisAccess() async {
    return hasActiveSubscription();
  }

  /// If subscribed (or in trial), navigates to [destination].
  /// Otherwise opens the Premium paywall with a return path.
  static Future<bool> openAnalysisOrPaywall(
    BuildContext context, {
    String destination = defaultAnalysisRoute,
    bool replace = false,
  }) async {
    final allowed = await checkAnalysisAccess();
    if (!context.mounted) return allowed;

    if (allowed) {
      if (replace) {
        context.go(destination);
      } else {
        context.push(destination);
      }
      return true;
    }

    final paywall =
        '$premiumRoute?next=${Uri.encodeComponent(destination)}';
    if (replace) {
      context.go(paywall);
    } else {
      context.push(paywall);
    }
    return false;
  }

  /// Routes that require an active subscription (real analysis capture).
  ///
  /// `/processing` is intentionally unlocked: upload/camera are already gated,
  /// and redirecting `/processing` → Premium drops GoRouter `extra: File`.
  static const analysisLockedRoutes = <String>{
    '/camera-capture',
    '/camera',
    '/video-upload',
    '/video-preview',
    '/record',
    '/upload',
    '/upload-shot',
    '/capture-shot',
    '/analyze-shot',
  };

  static bool isAnalysisLockedRoute(String location) {
    return analysisLockedRoutes.any(
      (route) => location == route || location.startsWith('$route/'),
    );
  }
}
