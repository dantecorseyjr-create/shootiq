import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/player_profile.dart';
import 'package:shootiq/pages/settings_page.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/achievements_service.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:shootiq/services/progress_analytics_service.dart';
import 'package:shootiq/services/subscription_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with TickerProviderStateMixin {
  static const _accountOptions = [
    (label: 'Training Preferences', icon: Icons.fitness_center_rounded),
    (label: 'Notifications', icon: Icons.notifications_none_rounded),
    (label: 'Privacy', icon: Icons.lock_outline_rounded),
    (label: 'Connected Devices', icon: Icons.devices_rounded),
    (label: 'Download My Data', icon: Icons.download_rounded),
    (label: 'Help & Support', icon: Icons.help_outline_rounded),
    (label: 'About ShootIQ', icon: Icons.info_outline_rounded),
  ];

  late final AnimationController _fadeController;
  late final AnimationController _staggerController;
  late final AnimationController _avatarController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _avatarScale;

  PlayerProgression _progression = AchievementsService.fromShots(const []);
  List<ProgressGoal> _goals = const [];
  final Set<String> _completedGoals = {};
  bool _isSubscribed = false;

  static SettingsSection? _settingsSectionForLabel(String label) {
    return switch (label) {
      'Account' => SettingsSection.account,
      'Training Preferences' => SettingsSection.training,
      'Notifications' => SettingsSection.notifications,
      'Privacy' => SettingsSection.privacy,
      'Connected Devices' => SettingsSection.connectedDevices,
      'Download My Data' => SettingsSection.dataExport,
      'Help & Support' => SettingsSection.support,
      'About ShootIQ' => SettingsSection.about,
      _ => null,
    };
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

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    _avatarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _avatarScale = Tween<double>(begin: 0.86, end: 1).animate(
      CurvedAnimation(parent: _avatarController, curve: Curves.easeOutBack),
    );

    _fadeController.forward();
    _staggerController.forward();
    _avatarController.forward();
    ProfileService.loadProfile();
    _loadCareerStats();
  }

  Future<void> _loadCareerStats() async {
    final snap = await ProgressAnalyticsService.load();
    await snap.syncProfileCache();
    final subscribed = await SubscriptionService.hasActiveSubscription();
    if (!mounted) return;
    setState(() {
      _progression = snap.progression;
      _goals = snap.goals;
      _isSubscribed = subscribed;
      _completedGoals
        ..clear()
        ..addAll(
          snap.goals.where((g) => g.completed).map((g) => g.title),
        );
    });
  }

  List<({String label, String value, IconData icon})> _careerStatRows(
    PlayerProgression progression,
  ) {
    final streak = progression.streak.currentDays;
    return [
      (
        label: 'Shots Analyzed',
        value: '${progression.shotsAnalyzed}',
        icon: Icons.sports_basketball_outlined,
      ),
      (
        label: 'Average Score',
        value: progression.shotsAnalyzed == 0
            ? '—'
            : '${progression.averageScore}',
        icon: Icons.analytics_outlined,
      ),
      (
        label: 'Best Score',
        value:
            progression.shotsAnalyzed == 0 ? '—' : '${progression.bestScore}',
        icon: Icons.emoji_events_outlined,
      ),
      (
        label: 'Current Streak',
        value: streak == 0
            ? '0 Days'
            : '$streak Day${streak == 1 ? '' : 's'}',
        icon: Icons.local_fire_department_outlined,
      ),
    ];
  }

  List<String> _goalTitles() {
    if (_goals.isNotEmpty) {
      return _goals.map((g) => g.title).toList();
    }
    final selected = OnboardingService.selectedGoal;
    return [
      if (selected != null && selected.trim().isNotEmpty) selected,
      'Reach 90 Average Score',
      'Analyze 100 Shots',
    ];
  }

  List<({String label, String value, IconData icon})> _playerInfoRows(
    PlayerProfile? profile,
  ) {
    return [
      (
        label: 'Height',
        value: profile?.heightLabel ?? '—',
        icon: Icons.height_rounded,
      ),
      (
        label: 'Weight',
        value: profile?.weightLabel ?? '—',
        icon: Icons.monitor_weight_outlined,
      ),
      (
        label: 'Dominant Hand',
        value: profile?.dominantHandLabel ?? '—',
        icon: Icons.back_hand_outlined,
      ),
      (
        label: 'Primary Position',
        value: profile?.positionLabel ?? '—',
        icon: Icons.sports_basketball_outlined,
      ),
      (
        label: 'Experience',
        value: profile?.experienceLabel ?? '—',
        icon: Icons.timeline_rounded,
      ),
      (
        label: 'Age',
        value: profile?.ageLabel ?? '—',
        icon: Icons.cake_outlined,
      ),
    ];
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _staggerController.dispose();
    _avatarController.dispose();
    super.dispose();
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
          begin: const Offset(0, 0.1),
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

  void _toggleGoal(String goal) {
    setState(() {
      if (_completedGoals.contains(goal)) {
        _completedGoals.remove(goal);
      } else {
        _completedGoals.add(goal);
      }
    });
  }

  Future<void> _signOut() async {
    ProfileService.clear();
    await AuthService.signOut();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          bottom: false,
          child: ValueListenableBuilder<PlayerProfile?>(
            valueListenable: ProfileService.profileListenable,
            builder: (context, profile, _) {
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _ProfileAppBar(),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.0,
                            end: 0.28,
                            child: _ProfileHeader(
                              avatarScale: _avatarScale,
                              displayName: profile?.fullName ?? 'Player',
                              subtitle: profile?.subtitle ??
                                  'Complete your profile',
                              photoUrl: profile?.photoUrl,
                              isSubscribed: _isSubscribed,
                              onEdit: () =>
                                  context.push(AppRoutes.editProfile),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.12,
                            end: 0.4,
                            child: const _SectionTitle(
                              title: 'Player Information',
                            ),
                          ),
                          const SizedBox(height: 12),
                          _staggered(
                            start: 0.16,
                            end: 0.45,
                            child: _PlayerInfoCard(
                              rows: _playerInfoRows(profile),
                              onRowTap: () =>
                                  context.push(AppRoutes.editProfile),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.26,
                            end: 0.52,
                            child: const _SectionTitle(title: 'Career Stats'),
                          ),
                          const SizedBox(height: 12),
                          _staggered(
                            start: 0.3,
                            end: 0.58,
                            child: _CareerStatsGrid(
                              stats: _careerStatRows(_progression),
                            ),
                          ),
                          if (_progression.reminders.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _staggered(
                              start: 0.34,
                              end: 0.6,
                              child: _ProfileReminders(
                                reminders: _progression.reminders,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          _staggered(
                            start: 0.36,
                            end: 0.62,
                            child: _ProfileStreakCard(
                              streak: _progression.streak,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.4,
                            end: 0.66,
                            child: _GoalsCard(
                              goals: _goalTitles(),
                              completed: _completedGoals,
                              onToggle: _toggleGoal,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.44,
                            end: 0.7,
                            child: const _SectionTitle(title: 'Challenges'),
                          ),
                          const SizedBox(height: 12),
                          _staggered(
                            start: 0.46,
                            end: 0.74,
                            child: _ProfileChallenges(
                              challenges: _progression.challenges,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.5,
                            end: 0.76,
                            child: const _SectionTitle(title: 'Achievements'),
                          ),
                          const SizedBox(height: 12),
                          _staggered(
                            start: 0.52,
                            end: 0.8,
                            child: _ProfileAchievements(
                              achievements: _progression.achievements,
                            ),
                          ),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.6,
                            end: 0.84,
                            child: _SubscriptionCard(
                              isSubscribed: _isSubscribed,
                              onManage: () => context.push(
                                _isSubscribed
                                    ? AppRoutes.subscription
                                    : '${AppRoutes.premium}?next=${Uri.encodeComponent(AppRoutes.cameraCapture)}',
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _staggered(
                            start: 0.68,
                            end: 0.9,
                            child: const _SectionTitle(title: 'Account'),
                          ),
                          const SizedBox(height: 12),
                          _staggered(
                            start: 0.72,
                            end: 0.95,
                            child: _AccountOptionsCard(
                              options: _accountOptions,
                              onOptionTap: (label) {
                                final section =
                                    _settingsSectionForLabel(label);
                                if (section == null) {
                                  context.push(AppRoutes.settings);
                                  return;
                                }
                                context.push(
                                  '${AppRoutes.settings}?section=${section.queryValue}',
                                  extra: section,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 24),
                          _staggered(
                            start: 0.8,
                            end: 1.0,
                            child: SizedBox(
                              height: 54,
                              child: OutlinedButton(
                                onPressed: _signOut,
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProfileAppBar extends StatelessWidget {
  const _ProfileAppBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Profile',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: ShootIQTheme.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
        ),
        Material(
          color: ShootIQTheme.surfaceElevated,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.push(
              '${AppRoutes.settings}?section=${SettingsSection.account.queryValue}',
              extra: SettingsSection.account,
            ),
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.edit_rounded,
                color: ShootIQTheme.textPrimary,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.avatarScale,
    required this.displayName,
    required this.subtitle,
    required this.onEdit,
    required this.isSubscribed,
    this.photoUrl,
  });

  final Animation<double> avatarScale;
  final String displayName;
  final String subtitle;
  final String? photoUrl;
  final bool isSubscribed;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Column(
      children: [
        GestureDetector(
          onTap: onEdit,
          child: ScaleTransition(
            scale: avatarScale,
            child: Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasPhoto
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ShootIQTheme.basketballOrange,
                          ShootIQTheme.basketballOrangeLight,
                        ],
                      ),
                image: hasPhoto
                    ? DecorationImage(
                        image: NetworkImage(photoUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color:
                        ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: ShootIQTheme.cardBorder,
                  width: 3,
                ),
              ),
              child: hasPhoto
                  ? null
                  : const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: ShootIQTheme.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: ShootIQTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSubscribed
                ? ShootIQTheme.primaryBlue
                : ShootIQTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSubscribed
                  ? ShootIQTheme.redBorder
                  : ShootIQTheme.cardBorder,
              width: isSubscribed ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSubscribed ? '⭐' : '○',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 6),
              Text(
                isSubscribed ? 'Premium Member' : 'Free Explorer',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isSubscribed
                      ? Colors.white
                      : ShootIQTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ShootIQTheme.textPrimary,
        letterSpacing: -0.3,
      ),
    );
  }
}

class _PlayerInfoCard extends StatelessWidget {
  const _PlayerInfoCard({
    required this.rows,
    this.onRowTap,
  });

  final List<({String label, String value, IconData icon})> rows;
  final VoidCallback? onRowTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: ShootIQTheme.cardBorder,
              ),
            InkWell(
              onTap: onRowTap,
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? const Radius.circular(22) : Radius.zero,
                bottom: i == rows.length - 1
                    ? const Radius.circular(22)
                    : Radius.zero,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: ShootIQTheme.basketballOrange
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        rows[i].icon,
                        color: ShootIQTheme.basketballOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rows[i].label,
                            style: const TextStyle(
                              fontSize: 13,
                              color: ShootIQTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            rows[i].value,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: ShootIQTheme.textPrimary,
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
          ],
        ],
      ),
    );
  }
}

class _CareerStatsGrid extends StatelessWidget {
  const _CareerStatsGrid({required this.stats});

  final List<({String label, String value, IconData icon})> stats;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ShootIQTheme.cardBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: ShootIQTheme.basketballOrange.withValues(alpha: 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  stat.icon,
                  color: ShootIQTheme.basketballOrange,
                  size: 20,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                stat.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: ShootIQTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stat.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: ShootIQTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard({
    required this.goals,
    required this.completed,
    required this.onToggle,
  });

  final List<String> goals;
  final Set<String> completed;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Goals',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ShootIQTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          for (final goal in goals)
            CheckboxListTile(
              value: completed.contains(goal),
              onChanged: (_) => onToggle(goal),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: ShootIQTheme.basketballOrange,
              checkColor: Colors.white,
              title: Text(
                goal,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: completed.contains(goal)
                      ? ShootIQTheme.textPrimary
                      : ShootIQTheme.textSecondary,
                  decoration: completed.contains(goal)
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: ShootIQTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileReminders extends StatelessWidget {
  const _ProfileReminders({required this.reminders});
  final List<ProgressionReminder> reminders;

  @override
  Widget build(BuildContext context) {
    final items = reminders.take(2).toList();
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: ShootIQTheme.basketballOrange.withValues(alpha: 0.12),
              border: Border.all(
                color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: ShootIQTheme.basketballOrange,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[i].message,
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < items.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ProfileStreakCard extends StatelessWidget {
  const _ProfileStreakCard({required this.streak});
  final StreakInfo streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                begin: 0,
                end: (streak.currentDays / 7).clamp(0.0, 1.0),
              ),
              duration: const Duration(milliseconds: 850),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return CustomPaint(
                  painter: _ProfileRingPainter(progress: value),
                  child: Center(
                    child: Text(
                      '${streak.currentDays}',
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Training Streak',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Longest ${streak.longestDays} days · Last ${streak.lastTrainingLabel}',
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _ProfileRingPainter extends CustomPainter {
  _ProfileRingPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final bg = Paint()
      ..color = ShootIQTheme.cardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final fg = Paint()
      ..color = ShootIQTheme.basketballOrange
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    canvas.drawCircle(center, radius, bg);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.28318 * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _ProfileRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ProfileChallenges extends StatelessWidget {
  const _ProfileChallenges({required this.challenges});
  final List<ChallengeItem> challenges;

  @override
  Widget build(BuildContext context) {
    // Keep Profile compact: top daily + weekly + monthly highlight.
    final spotlight = <ChallengeItem>[
      ...challenges.where((c) => c.period == ChallengePeriod.daily).take(2),
      ...challenges.where((c) => c.period == ChallengePeriod.weekly).take(1),
      ...challenges.where((c) => c.period == ChallengePeriod.monthly).take(1),
    ];

    return Column(
      children: [
        for (final challenge in spotlight) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ShootIQTheme.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ShootIQTheme.basketballOrange
                            .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        challenge.periodLabel,
                        style: const TextStyle(
                          color: ShootIQTheme.basketballOrange,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${challenge.percentComplete}%',
                      style: TextStyle(
                        color: challenge.completed
                            ? const Color(0xFF22C55E)
                            : ShootIQTheme.basketballOrange,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  challenge.title,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: challenge.progress,
                    minHeight: 7,
                    backgroundColor: ShootIQTheme.cardBorder,
                    valueColor: AlwaysStoppedAnimation(
                      challenge.completed
                          ? const Color(0xFF22C55E)
                          : ShootIQTheme.basketballOrange,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${challenge.progressLabel} · Reward: ${challenge.reward}',
                  style: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (challenge != spotlight.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ProfileAchievements extends StatelessWidget {
  const _ProfileAchievements({required this.achievements});
  final List<AchievementBadge> achievements;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final badge in achievements) ...[
          _ProfileAchievementTile(badge: badge),
          if (badge != achievements.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ProfileAchievementTile extends StatefulWidget {
  const _ProfileAchievementTile({required this.badge});
  final AchievementBadge badge;

  @override
  State<_ProfileAchievementTile> createState() =>
      _ProfileAchievementTileState();
}

class _ProfileAchievementTileState extends State<_ProfileAchievementTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _unlock;

  @override
  void initState() {
    super.initState();
    _unlock = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    if (widget.badge.completed) {
      _unlock.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _ProfileAchievementTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.badge.completed && !oldWidget.badge.completed) {
      _unlock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _unlock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = widget.badge;
    final accent = badge.completed
        ? ShootIQTheme.basketballOrange
        : badge.inProgress
            ? const Color(0xFFFBBF24)
            : ShootIQTheme.textSecondary;

    return ScaleTransition(
      scale: Tween<double>(begin: 0.97, end: 1).animate(
        CurvedAnimation(parent: _unlock, curve: Curves.easeOutBack),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: badge.completed
              ? ShootIQTheme.basketballOrange.withValues(alpha: 0.12)
              : ShootIQTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: badge.completed
                ? ShootIQTheme.basketballOrange.withValues(alpha: 0.4)
                : ShootIQTheme.cardBorder,
          ),
        ),
        child: Row(
          children: [
            Text(badge.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          badge.title,
                          style: TextStyle(
                            color: badge.locked
                                ? ShootIQTheme.textSecondary
                                : ShootIQTheme.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(
                        badge.statusLabel,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    badge.description,
                    style: const TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: badge.progress,
                      minHeight: 6,
                      backgroundColor: ShootIQTheme.cardBorder,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    badge.progressLabel,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.onManage,
    required this.isSubscribed,
  });

  final VoidCallback onManage;
  final bool isSubscribed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ShootIQTheme.cardBackground,
            ShootIQTheme.surfaceElevated,
            ShootIQTheme.basketballOrange.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(
          color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isSubscribed ? 'ShootIQ Pro' : 'Unlock ShootIQ Pro',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: ShootIQTheme.textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isSubscribed
                      ? const Color(0xFF22C55E).withValues(alpha: 0.18)
                      : ShootIQTheme.cardBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isSubscribed ? 'Active' : 'Inactive',
                  style: TextStyle(
                    color: isSubscribed
                        ? const Color(0xFF22C55E)
                        : ShootIQTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isSubscribed
                ? 'Premium access unlocked — including active free trials.'
                : 'Start a 3-day free trial on Yearly, or continue with Monthly / Weekly.',
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          const _ProPerk(text: 'Unlimited AI Shot Analysis'),
          const _ProPerk(text: 'AI Shooting Coach'),
          const _ProPerk(text: 'Movement Breakdown'),
          const _ProPerk(text: 'Shot History & Progress'),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: onManage,
              style: FilledButton.styleFrom(
                backgroundColor: ShootIQTheme.buttonBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(
                isSubscribed
                    ? 'Manage Subscription'
                    : 'Start 3-Day Free Trial',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProPerk extends StatelessWidget {
  const _ProPerk({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 18,
            color: ShootIQTheme.basketballOrange,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              color: ShootIQTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountOptionsCard extends StatelessWidget {
  const _AccountOptionsCard({
    required this.options,
    required this.onOptionTap,
  });

  final List<({String label, IconData icon})> options;
  final ValueChanged<String> onOptionTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: ShootIQTheme.cardBorder),
            InkWell(
              onTap: () => onOptionTap(options[i].label),
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? const Radius.circular(22) : Radius.zero,
                bottom: i == options.length - 1
                    ? const Radius.circular(22)
                    : Radius.zero,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                child: Row(
                  children: [
                    Icon(
                      options[i].icon,
                      color: ShootIQTheme.basketballOrange,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        options[i].label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ShootIQTheme.textPrimary,
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
          ],
        ],
      ),
    );
  }
}
