import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/app_preferences_service.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:shootiq/services/subscription_service.dart';

/// Sections on the Settings page that Profile (and deep links) can open.
enum SettingsSection {
  account,
  notifications,
  training,
  privacy,
  connectedDevices,
  dataExport,
  support,
  about;

  static SettingsSection? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll('-', '')
        .replaceAll('_', '')
        .replaceAll(' ', '');
    return switch (normalized) {
      'account' => SettingsSection.account,
      'notifications' => SettingsSection.notifications,
      'training' || 'trainingpreferences' => SettingsSection.training,
      'privacy' => SettingsSection.privacy,
      'connecteddevices' => SettingsSection.connectedDevices,
      'dataexport' || 'data' || 'export' => SettingsSection.dataExport,
      'support' || 'help' => SettingsSection.support,
      'about' => SettingsSection.about,
      _ => null,
    };
  }

  String get queryValue => switch (this) {
        SettingsSection.connectedDevices => 'connectedDevices',
        SettingsSection.dataExport => 'dataExport',
        _ => name,
      };

  /// Expandable group this deep-link targets.
  SettingsSection get expandGroup => switch (this) {
        SettingsSection.connectedDevices => SettingsSection.account,
        _ => this,
      };
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.initialSection});

  final SettingsSection? initialSection;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final AnimationController _staggerController;
  late final AnimationController _highlightController;
  late final Animation<double> _fadeAnimation;
  late final ScrollController _scrollController;

  final Map<SettingsSection, GlobalKey> _sectionKeys = {
    for (final section in SettingsSection.values)
      if (section != SettingsSection.connectedDevices) section: GlobalKey(),
  };
  final GlobalKey _connectedDevicesKey = GlobalKey();

  SettingsSection? _expandedSection;
  SettingsSection? _highlightedSection;
  AppPreferences _prefs = const AppPreferences();
  bool _subscribed = false;
  String _subscriptionLabel = 'Free';
  String? _accountEmail;

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
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _scrollController = ScrollController();

    final target = widget.initialSection;
    if (target != null) {
      _expandedSection = target.expandGroup;
      _highlightedSection = target.expandGroup;
    }

    _fadeController.forward();
    _staggerController.forward();
    _loadStatus();

    if (target != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusSection(target);
      });
    }
  }

  Future<void> _loadStatus() async {
    final results = await Future.wait([
      AppPreferencesService.load(),
      SubscriptionService.hasActiveSubscription(),
      SubscriptionService.statusLabel(),
    ]);
    if (!mounted) return;
    setState(() {
      _prefs = results[0] as AppPreferences;
      _subscribed = results[1] as bool;
      _subscriptionLabel = results[2] as String;
      _accountEmail = AuthService.currentUser?.email;
    });
  }

  Future<void> _updatePrefs(AppPreferences next) async {
    setState(() => _prefs = next);
    await AppPreferencesService.save(next);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection != oldWidget.initialSection &&
        widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusSection(widget.initialSection!);
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _staggerController.dispose();
    _highlightController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _focusSection(SettingsSection section) async {
    final group = section.expandGroup;
    if (!mounted) return;

    setState(() {
      _expandedSection = group;
      _highlightedSection = group;
    });

    // Wait for expand animation / layout before scrolling.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;

    final key = section == SettingsSection.connectedDevices
        ? _connectedDevicesKey
        : _sectionKeys[group];
    final targetContext = key?.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    }

    if (!mounted) return;
    _highlightController
      ..reset()
      ..forward().whenComplete(() {
        if (mounted) {
          setState(() => _highlightedSection = null);
        }
      });
  }

  void _toggleSection(SettingsSection section) {
    setState(() {
      _expandedSection = _expandedSection == section ? null : section;
    });
  }

  Widget _staggered({
    required double start,
    required double end,
    required Widget child,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut),
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _staggerController,
            curve: Interval(start, end, curve: Curves.easeOutCubic),
          ),
        ),
        child: child,
      ),
    );
  }

  Future<void> _pickWorkoutLength() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: ShootIQTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ShootIQTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Default Workout Length',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (final minutes in const [15, 30, 60])
                  ListTile(
                    title: Text(
                      '$minutes minutes',
                      style: TextStyle(
                        color: _prefs.defaultWorkoutMinutes == minutes
                            ? ShootIQTheme.basketballOrange
                            : ShootIQTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    trailing: _prefs.defaultWorkoutMinutes == minutes
                        ? const Icon(
                            Icons.check_rounded,
                            color: ShootIQTheme.basketballOrange,
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(minutes),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await _updatePrefs(_prefs.copyWith(defaultWorkoutMinutes: selected));
    }
  }

  void _showConnectedDevicesSheet() {
    final email = _accountEmail ?? 'Signed in';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ShootIQTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ShootIQTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Connected Devices',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ShootIQTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.phone_iphone_rounded,
                  color: ShootIQTheme.primaryBlue,
                ),
                title: const Text(
                  'This device',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(email),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ShootIQTheme.primaryBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(
                      color: ShootIQTheme.primaryBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Multi-device management will appear here once account device sync is enabled.',
                style: TextStyle(
                  color: ShootIQTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showWhatsNewSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ShootIQTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "What's New",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: ShootIQTheme.textPrimary,
                ),
              ),
              SizedBox(height: 12),
              Text(
                '• Privacy-first shot storage (videos stay on your device)\n'
                '• Yearly plan with 3-day free trial\n'
                '• Export shot history as CSV/JSON\n'
                '• Expanded Help Center and support tools',
                style: TextStyle(
                  color: ShootIQTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _clearCache() async {
    // Best-effort clear of temporary analysis staging files.
    try {
      final temp = await getTemporaryDirectory();
      var removed = 0;
      await for (final entity in temp.list()) {
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if (name.startsWith('shootiq_') ||
            name.startsWith('analysis_') ||
            name.contains('shootiq_data_') ||
            name.contains('shootiq_history_')) {
          try {
            await entity.delete(recursive: true);
            removed++;
          } catch (_) {}
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared $removed temporary cache item(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear cache: $e')),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ShootIQTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Sign Out?',
            style: TextStyle(
              color: ShootIQTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'You can sign back in anytime to continue training.',
            style: TextStyle(color: ShootIQTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: ShootIQTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Sign Out',
                style: TextStyle(
                  color: ShootIQTheme.errorRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true || !mounted) return;
    ProfileService.clear();
    await AuthService.signOut();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Widget _buildExpandableSection({
    required SettingsSection section,
    required String title,
    required IconData icon,
    required List<Widget> children,
    required double staggerStart,
    required double staggerEnd,
  }) {
    final isExpanded = _expandedSection == section;
    final isHighlighted = _highlightedSection == section;

    return _staggered(
      start: staggerStart,
      end: staggerEnd,
      child: KeyedSubtree(
        key: _sectionKeys[section],
        child: AnimatedBuilder(
          animation: _highlightController,
          builder: (context, child) {
            final highlightT = isHighlighted
                ? (1.0 - _highlightController.value).clamp(0.0, 1.0)
                : 0.0;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: ShootIQTheme.cardBackground,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Color.lerp(
                        ShootIQTheme.cardBorder,
                        ShootIQTheme.basketballOrange,
                        highlightT * 0.85,
                      ) ??
                      ShootIQTheme.cardBorder,
                  width: highlightT > 0.05 ? 1.6 : 1,
                ),
                boxShadow: highlightT > 0.05
                    ? [
                        BoxShadow(
                          color: ShootIQTheme.basketballOrange
                              .withValues(alpha: 0.22 * highlightT),
                          blurRadius: 18 * highlightT,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: child,
            );
          },
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _toggleSection(section),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: ShootIQTheme.basketballOrange
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          icon,
                          color: ShootIQTheme.basketballOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ShootIQTheme.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: ShootIQTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  heightFactor: isExpanded ? 1 : 0,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      Divider(
                        height: 1,
                        color: ShootIQTheme.cardBorder,
                      ),
                      ...children,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SettingsAppBar(),
                      const SizedBox(height: 24),
                      _staggered(
                        start: 0.0,
                        end: 0.28,
                        child: _StatusBanner(
                          email: _accountEmail,
                          subscribed: _subscribed,
                          onManageSubscription: () =>
                              context.push(AppRoutes.manageSubscription),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildExpandableSection(
                        section: SettingsSection.account,
                        title: 'Account',
                        icon: Icons.person_outline_rounded,
                        staggerStart: 0.05,
                        staggerEnd: 0.35,
                        children: [
                          _NavSettingTile(
                            icon: Icons.badge_outlined,
                            title: 'Profile Information',
                            subtitle: 'Update your player details',
                            onTap: () =>
                                context.push(AppRoutes.editProfile),
                          ),
                          _NavSettingTile(
                            icon: Icons.workspace_premium_outlined,
                            title: 'Subscription',
                            subtitle: _subscribed
                                ? _subscriptionLabel
                                : 'Free plan · 3-day yearly trial available',
                            onTap: () =>
                                context.push(AppRoutes.manageSubscription),
                          ),
                          _NavSettingTile(
                            icon: Icons.restore_rounded,
                            title: 'Restore Purchases',
                            subtitle: 'Recover an existing subscription',
                            onTap: () =>
                                context.push(AppRoutes.restorePurchases),
                          ),
                          _NavSettingTile(
                            icon: Icons.lock_outline_rounded,
                            title: 'Account Security',
                            subtitle: 'Password and login settings',
                            onTap: () =>
                                context.push(AppRoutes.forgotPassword),
                          ),
                          KeyedSubtree(
                            key: _connectedDevicesKey,
                            child: _NavSettingTile(
                              icon: Icons.devices_rounded,
                              title: 'Connected Devices',
                              subtitle: 'This device is signed in',
                              onTap: () => _showConnectedDevicesSheet(),
                              showDivider: false,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildExpandableSection(
                        section: SettingsSection.notifications,
                        title: 'Notifications',
                        icon: Icons.notifications_none_rounded,
                        staggerStart: 0.1,
                        staggerEnd: 0.42,
                        children: [
                          _ToggleSettingTile(
                            icon: Icons.notifications_active_outlined,
                            title: 'Push Notifications',
                            subtitle: 'Alerts on this device',
                            value: _prefs.pushNotifications,
                            onChanged: (value) {
                              _updatePrefs(
                                _prefs.copyWith(pushNotifications: value),
                              );
                            },
                          ),
                          _ToggleSettingTile(
                            icon: Icons.mail_outline_rounded,
                            title: 'Email Notifications',
                            subtitle: 'Updates in your inbox',
                            value: _prefs.emailNotifications,
                            onChanged: (value) {
                              _updatePrefs(
                                _prefs.copyWith(emailNotifications: value),
                              );
                            },
                          ),
                          _ToggleSettingTile(
                            icon: Icons.alarm_rounded,
                            title: 'Training Reminders',
                            subtitle: 'Stay consistent with practice',
                            value: _prefs.trainingReminders,
                            onChanged: (value) {
                              _updatePrefs(
                                _prefs.copyWith(trainingReminders: value),
                              );
                            },
                          ),
                          _ToggleSettingTile(
                            icon: Icons.insights_outlined,
                            title: 'Weekly Progress Reports',
                            subtitle: 'Summary of your week',
                            value: _prefs.weeklyProgressReports,
                            onChanged: (value) {
                              _updatePrefs(
                                _prefs.copyWith(weeklyProgressReports: value),
                              );
                            },
                            showDivider: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildExpandableSection(
                        section: SettingsSection.training,
                        title: 'Training Preferences',
                        icon: Icons.fitness_center_rounded,
                        staggerStart: 0.14,
                        staggerEnd: 0.48,
                        children: [
                          _NavSettingTile(
                            icon: Icons.timer_outlined,
                            title: 'Default Workout Length',
                            subtitle: '${_prefs.defaultWorkoutMinutes} minutes',
                            onTap: () => _pickWorkoutLength(),
                          ),
                          _ToggleSettingTile(
                            icon: Icons.back_hand_outlined,
                            title: 'Dominant Hand Focus',
                            subtitle: 'Prioritize drills for your shooting hand',
                            value: _prefs.focusDominantHandOnly,
                            onChanged: (value) {
                              _updatePrefs(
                                _prefs.copyWith(focusDominantHandOnly: value),
                              );
                            },
                          ),
                          _NavSettingTile(
                            icon: Icons.sports_basketball_outlined,
                            title: 'Open AI Drills',
                            subtitle: 'Personalized workouts from your weaknesses',
                            onTap: () => context.push(AppRoutes.drills),
                            showDivider: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildExpandableSection(
                        section: SettingsSection.privacy,
                        title: 'Privacy Controls',
                        icon: Icons.shield_outlined,
                        staggerStart: 0.18,
                        staggerEnd: 0.52,
                        children: [
                          _ToggleSettingTile(
                            icon: Icons.public_off_rounded,
                            title: 'Share Progress Publicly',
                            subtitle: 'Allow others to see career highlights',
                            value: _prefs.shareProgressPublicly,
                            onChanged: (value) {
                              _updatePrefs(
                                _prefs.copyWith(shareProgressPublicly: value),
                              );
                            },
                          ),
                          _ToggleSettingTile(
                            icon: Icons.analytics_outlined,
                            title: 'Usage Analytics',
                            subtitle: 'Help improve ShootIQ with anonymous data',
                            value: _prefs.analyticsEnabled,
                            onChanged: (value) {
                              _updatePrefs(
                                _prefs.copyWith(analyticsEnabled: value),
                              );
                            },
                          ),
                          _SimpleSettingTile(
                            title: 'Privacy Policy',
                            onTap: () =>
                                context.push(AppRoutes.privacyPolicy),
                          ),
                          _SimpleSettingTile(
                            title: 'Terms of Service',
                            onTap: () =>
                                context.push(AppRoutes.termsOfService),
                          ),
                          _SimpleSettingTile(
                            title: 'Delete Account',
                            titleColor: ShootIQTheme.errorRed,
                            onTap: () =>
                                context.push(AppRoutes.deleteAccount),
                            showDivider: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildExpandableSection(
                        section: SettingsSection.dataExport,
                        title: 'Data & Export',
                        icon: Icons.folder_outlined,
                        staggerStart: 0.24,
                        staggerEnd: 0.58,
                        children: [
                          _NavSettingTile(
                            icon: Icons.download_rounded,
                            title: 'Download My Data',
                            subtitle: 'Request a copy of your data',
                            onTap: () =>
                                context.push(AppRoutes.downloadMyData),
                          ),
                          _NavSettingTile(
                            icon: Icons.history_rounded,
                            title: 'Export Shot History',
                            subtitle: 'Save your analysis history',
                            onTap: () =>
                                context.push(AppRoutes.exportShotHistory),
                          ),
                          _NavSettingTile(
                            icon: Icons.cleaning_services_outlined,
                            title: 'Clear Cache',
                            subtitle: 'Free up local storage',
                            onTap: () => _clearCache(),
                            showDivider: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildExpandableSection(
                        section: SettingsSection.support,
                        title: 'Support',
                        icon: Icons.help_outline_rounded,
                        staggerStart: 0.32,
                        staggerEnd: 0.68,
                        children: [
                          _SimpleSettingTile(
                            title: 'Help Center',
                            onTap: () => context.push(AppRoutes.helpCenter),
                          ),
                          _SimpleSettingTile(
                            title: 'Contact Support',
                            onTap: () =>
                                context.push(AppRoutes.contactSupport),
                          ),
                          _SimpleSettingTile(
                            title: 'Report a Problem',
                            onTap: () =>
                                context.push(AppRoutes.reportProblem),
                          ),
                          _SimpleSettingTile(
                            title: 'Rate ShootIQ',
                            onTap: () => context.push(AppRoutes.rateShootIq),
                            showDivider: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildExpandableSection(
                        section: SettingsSection.about,
                        title: 'About',
                        icon: Icons.info_outline_rounded,
                        staggerStart: 0.4,
                        staggerEnd: 0.78,
                        children: [
                          _SimpleSettingTile(
                            title: "What's New",
                            onTap: () => _showWhatsNewSheet(),
                          ),
                          _SimpleSettingTile(
                            title: 'Open Source Licenses',
                            onTap: () => showLicensePage(
                              context: context,
                              applicationName: 'ShootIQ',
                              applicationVersion: '1.0.0',
                            ),
                          ),
                          _SimpleSettingTile(
                            title: 'About ShootIQ',
                            onTap: () => context.push(AppRoutes.about),
                            showDivider: false,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: _confirmSignOut,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ShootIQTheme.errorRed,
                            side: const BorderSide(
                              color: ShootIQTheme.errorRed,
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Sign Out'),
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.email,
    required this.subscribed,
    required this.onManageSubscription,
  });

  final String? email;
  final bool subscribed;
  final VoidCallback onManageSubscription;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: subscribed
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.4)
              : ShootIQTheme.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: subscribed
                      ? const Color(0xFF22C55E)
                      : ShootIQTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                subscribed ? 'Account Active' : 'Free Account',
                style: const TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: subscribed
                      ? ShootIQTheme.basketballOrange.withValues(alpha: 0.18)
                      : ShootIQTheme.cardBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  subscribed ? 'Pro' : 'Free',
                  style: TextStyle(
                    color: subscribed
                        ? ShootIQTheme.basketballOrange
                        : ShootIQTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (email != null && email!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              email!,
              style: const TextStyle(
                color: ShootIQTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onManageSubscription,
              style: OutlinedButton.styleFrom(
                foregroundColor: ShootIQTheme.basketballOrange,
                side: BorderSide(
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                subscribed ? 'Manage Subscription' : 'Upgrade to ShootIQ Pro',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsAppBar extends StatelessWidget {
  const _SettingsAppBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: ShootIQTheme.surfaceElevated,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(AppRoutes.profile);
              }
            },
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: ShootIQTheme.textPrimary,
              ),
            ),
          ),
        ),
        const Expanded(
          child: Text(
            'Settings',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ShootIQTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}

class _NavSettingTile extends StatelessWidget {
  const _NavSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ShootIQTheme.basketballOrange.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: ShootIQTheme.basketballOrange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: ShootIQTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ShootIQTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: ShootIQTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 70,
            color: ShootIQTheme.cardBorder,
          ),
      ],
    );
  }
}

class _ToggleSettingTile extends StatelessWidget {
  const _ToggleSettingTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: ShootIQTheme.basketballOrange, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ShootIQTheme.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: ShootIQTheme.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: ShootIQTheme.basketballOrange,
                activeTrackColor:
                    ShootIQTheme.basketballOrange.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 52,
            color: ShootIQTheme.cardBorder,
          ),
      ],
    );
  }
}

class _SimpleSettingTile extends StatelessWidget {
  const _SimpleSettingTile({
    required this.title,
    required this.onTap,
    this.titleColor = ShootIQTheme.textPrimary,
    this.showDivider = true,
  });

  final String title;
  final VoidCallback onTap;
  final Color titleColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: ShootIQTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 16,
            color: ShootIQTheme.cardBorder,
          ),
      ],
    );
  }
}
