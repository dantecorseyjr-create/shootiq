import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

class _GoalOption {
  const _GoalOption({
    required this.emoji,
    required this.title,
    required this.description,
  });

  final String emoji;
  final String title;
  final String description;
}

const _goalOptions = [
  _GoalOption(
    emoji: '🏀',
    title: 'Improve My Shooting Form',
    description: 'Fix mechanics and build a smoother shot.',
  ),
  _GoalOption(
    emoji: '🎯',
    title: 'Become More Accurate',
    description: 'Improve consistency and shooting percentage.',
  ),
  _GoalOption(
    emoji: '⚡',
    title: 'Create A Faster Release',
    description: 'Get your shot off quicker in games.',
  ),
  _GoalOption(
    emoji: '🔥',
    title: 'Increase My Range',
    description: 'Develop confidence from deeper distances.',
  ),
  _GoalOption(
    emoji: '🏆',
    title: 'Prepare For Competition',
    description: 'Train like a serious player.',
  ),
];

class GoalPage extends StatefulWidget {
  const GoalPage({super.key});

  @override
  State<GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<GoalPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = OnboardingService.selectedGoalIndex;
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (_selectedIndex == null) return;

    final goal = _goalOptions[_selectedIndex!];
    OnboardingService.selectedGoalIndex = _selectedIndex;
    OnboardingService.selectedGoal = goal.title;

    context.push(AppRoutes.helpStart);
  }

  @override
  Widget build(BuildContext context) {
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
                      const OnboardingIllustration(
                        assetPath: 'assets/images/goal.png',
                        fallbackIcon: Icons.flag_outlined,
                        placeholderColor: PremiumColors.cardBackground,
                      ),
                      const SizedBox(height: PremiumSpacing.heroToTitle),
                      const _TitleSection(),
                      const SizedBox(height: PremiumSpacing.section),
                      _GoalOptionsList(
                        selectedIndex: _selectedIndex,
                        onSelected: (index) {
                          setState(() => _selectedIndex = index);
                        },
                      ),
                      const SizedBox(height: 28),
                      OnboardingPrimaryButton(
                        label: 'Continue',
                        backgroundColor: PremiumColors.accentOrange,
                        onPressed:
                            _selectedIndex != null ? _onContinue : null,
                      ),
                      const SizedBox(height: 16),
                      const OnboardingFootnote(
                        text:
                            'Your AI coach will adjust recommendations based on your goal.',
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

class _TitleSection extends StatelessWidget {
  const _TitleSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'What Are You Working On?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.black,
                height: 1.15,
                letterSpacing: -0.8,
              ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: const Text(
            'Tell us your goal so ShotIQ can personalize your coaching.',
            textAlign: TextAlign.center,
            style: TextStyle(
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

class _GoalOptionsList extends StatelessWidget {
  const _GoalOptionsList({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _goalOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: PremiumSpacing.goalCardGap),
          GoalOptionCard(
            emoji: _goalOptions[i].emoji,
            title: _goalOptions[i].title,
            description: _goalOptions[i].description,
            isSelected: selectedIndex == i,
            onTap: () => onSelected(i),
          ),
        ],
      ],
    );
  }
}
