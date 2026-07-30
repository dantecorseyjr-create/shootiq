import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/subscription_service.dart';

/// Camera / upload selection hub after subscription check.
class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
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

  Future<void> _openRecord() async {
    await SubscriptionService.openAnalysisOrPaywall(
      context,
      destination: AppRoutes.cameraCapture,
    );
  }

  Future<void> _openUpload() async {
    await SubscriptionService.openAnalysisOrPaywall(
      context,
      destination: AppRoutes.videoUpload,
    );
  }

  void _onBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.analyze);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _onBack,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: ShootIQTheme.textPrimary,
                        size: 20,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Analyze Your Shot',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        ShootIQTheme.surfaceElevated,
                        ShootIQTheme.basketballOrange.withValues(alpha: 0.16),
                      ],
                    ),
                    border: Border.all(
                      color: ShootIQTheme.cardBorder,
                    ),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'Capture or Upload',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Record a 15-second clip or choose a video from your library.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                _OptionCard(
                  icon: Icons.videocam_rounded,
                  title: 'Record Video',
                  description:
                      'Open the camera. Flip front/back. Max 15 seconds.',
                  buttonLabel: 'Record Video',
                  onPressed: _openRecord,
                ),
                const SizedBox(height: 12),
                _OptionCard(
                  icon: Icons.photo_library_outlined,
                  title: 'Upload From Library',
                  description:
                      'Pick an existing shot clip from your device.',
                  buttonLabel: 'Upload From Library',
                  onPressed: _openUpload,
                ),
                const Spacer(),
                Text(
                  'Tip: Side angle, full body in frame, steady camera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: ShootIQTheme.basketballOrange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              color: ShootIQTheme.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: ShootIQTheme.buttonBlue,
                foregroundColor: Colors.white,
                side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                          shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }
}
