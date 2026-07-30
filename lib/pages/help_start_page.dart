import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

class _HelpStartOption {
  const _HelpStartOption({
    required this.emoji,
    required this.title,
    required this.description,
  });

  final String emoji;
  final String title;
  final String description;
}

const _helpStartOptions = [
  _HelpStartOption(
    emoji: '🏀',
    title: 'Improve My Shooting Form',
    description: 'Fix mechanics and build a more consistent shot.',
  ),
  _HelpStartOption(
    emoji: '🎯',
    title: 'Increase My Shooting Accuracy',
    description: 'Make more shots with better consistency.',
  ),
  _HelpStartOption(
    emoji: '⚡',
    title: 'Improve My Release Speed',
    description: 'Get your shot off faster in game situations.',
  ),
  _HelpStartOption(
    emoji: '🏆',
    title: 'Prepare For Games',
    description: 'Train with personalized drills and feedback.',
  ),
  _HelpStartOption(
    emoji: '📈',
    title: 'Track My Progress',
    description: 'Monitor your shooting score and improvement over time.',
  ),
  _HelpStartOption(
    emoji: '🤷',
    title: 'Explore Everything',
    description: 'Show me everything ShotIQ can do.',
  ),
];

class HelpStartPage extends StatefulWidget {
  const HelpStartPage({super.key});

  @override
  State<HelpStartPage> createState() => _HelpStartPageState();
}

class _HelpStartPageState extends State<HelpStartPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  int? _selectedIndex;

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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onContinue() {
    if (_selectedIndex == null) return;
    context.push(AppRoutes.confidence);
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
                        assetPath: 'assets/images/help_start.png',
                        fallbackIcon: Icons.sports_basketball_outlined,
                        placeholderColor: PremiumColors.cardBackground,
                      ),
                      const SizedBox(height: PremiumSpacing.heroToTitle),
                      const OnboardingTitleSection(
                        title: 'Where Should We Help You Start?',
                        subtitle:
                            'Choose what matters most to you right now.',
                      ),
                      const SizedBox(height: PremiumSpacing.section),
                      _HelpStartOptionsList(
                        selectedIndex: _selectedIndex,
                        onSelected: (index) =>
                            setState(() => _selectedIndex = index),
                      ),
                      const SizedBox(height: 32),
                      OnboardingPrimaryButton(
                        label: 'Continue',
                        backgroundColor: PremiumColors.accentOrange,
                        onPressed:
                            _selectedIndex != null ? _onContinue : null,
                      ),
                      const SizedBox(height: 24),
                      const OnboardingFootnote(
                        text:
                            "Don't worry—you can change this later in Settings.",
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

class _HelpStartOptionsList extends StatelessWidget {
  const _HelpStartOptionsList({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _helpStartOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: PremiumSpacing.goalCardGap),
          GoalOptionCard(
            height: 74,
            emoji: _helpStartOptions[i].emoji,
            title: _helpStartOptions[i].title,
            description: _helpStartOptions[i].description,
            isSelected: selectedIndex == i,
            onTap: () => onSelected(i),
          ),
        ],
      ],
    );
  }
}
