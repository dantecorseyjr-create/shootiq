import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

const _page2Features = [
  (
    icon: Icons.videocam_outlined,
    title: 'Capture Your Shot',
    description: 'Record or upload a video of your shooting form.',
  ),
  (
    icon: Icons.psychology_outlined,
    title: 'Get AI Feedback',
    description: 'ShotIQ analyzes your mechanics in seconds.',
  ),
  (
    icon: Icons.trending_up_rounded,
    title: 'Train With Purpose',
    description: 'Follow personalized drills based on your goal.',
  ),
];

class Page2Page extends StatefulWidget {
  const Page2Page({super.key});

  @override
  State<Page2Page> createState() => _Page2PageState();
}

class _Page2PageState extends State<Page2Page>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

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

  void _onContinue() => context.push(AppRoutes.signup);

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
                      Text(
                        'Your Free Trial Starts Now',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
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
                          'Next, we\'ll set up your camera and personalize your AI shooting coach.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: PremiumColors.subtitle,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: PremiumSpacing.section),
                      for (var i = 0; i < _page2Features.length; i++) ...[
                        if (i > 0)
                          const SizedBox(height: PremiumSpacing.cardGap),
                        PremiumFeatureCard(
                          icon: _page2Features[i].icon,
                          title: _page2Features[i].title,
                          description: _page2Features[i].description,
                        ),
                      ],
                      const SizedBox(height: 28),
                      OnboardingPrimaryButton(
                        label: 'Continue',
                        backgroundColor: PremiumColors.accentOrange,
                        onPressed: _onContinue,
                      ),
                      const SizedBox(height: 16),
                      const OnboardingFootnote(
                        text: 'Takes less than a minute to get started.',
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
