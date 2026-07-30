import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/widgets/back_button.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';
import 'package:shootiq/widgets/shot_upload/shot_upload_widgets.dart';

enum _ShotSource { record, upload }

class ShotUploadPage extends StatefulWidget {
  const ShotUploadPage({super.key});

  @override
  State<ShotUploadPage> createState() => _ShotUploadPageState();
}

class _ShotUploadPageState extends State<ShotUploadPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  final _picker = ImagePicker();
  _ShotSource? _selectedSource;
  bool _isBusy = false;

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

  Future<void> _openCamera() async {
    if (_isBusy) return;
    setState(() {
      _selectedSource = _ShotSource.record;
      _isBusy = true;
    });

    try {
      await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
    } catch (_) {
      // Camera capture unavailable — selection still counts.
    }

    if (mounted) setState(() => _isBusy = false);
  }

  Future<void> _openGallery() async {
    if (_isBusy) return;
    setState(() {
      _selectedSource = _ShotSource.upload;
      _isBusy = true;
    });

    try {
      await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
    } catch (_) {
      // Gallery picker unavailable — selection still counts.
    }

    if (mounted) setState(() => _isBusy = false);
  }

  void _onContinue() {
    if (_selectedSource == null) return;
    context.push(AppRoutes.goal);
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selectedSource != null && !_isBusy;

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
                      const ShotUploadHero(),
                      const SizedBox(height: PremiumSpacing.heroToTitle),
                      const _TitleSection(),
                      const SizedBox(height: PremiumSpacing.section),
                      ShotSourceCard(
                        emoji: '📹',
                        title: 'Record A Shot',
                        description:
                            'Use your camera to capture your shooting form.',
                        buttonLabel: 'Record Now',
                        isSelected: _selectedSource == _ShotSource.record,
                        onSelect: () => setState(
                          () => _selectedSource = _ShotSource.record,
                        ),
                        onAction: _openCamera,
                      ),
                      const SizedBox(height: PremiumSpacing.goalCardGap),
                      ShotSourceCard(
                        emoji: '🎞️',
                        title: 'Upload From Library',
                        description:
                            'Choose an existing shooting video from your phone.',
                        buttonLabel: 'Choose Video',
                        isSelected: _selectedSource == _ShotSource.upload,
                        onSelect: () => setState(
                          () => _selectedSource = _ShotSource.upload,
                        ),
                        onAction: _openGallery,
                      ),
                      const SizedBox(height: 28),
                      OnboardingPrimaryButton(
                        label: 'Continue',
                        backgroundColor: PremiumColors.accentOrange,
                        onPressed: canContinue ? _onContinue : null,
                      ),
                      const SizedBox(height: 16),
                      const OnboardingFootnote(
                        text:
                            'Your video is analyzed securely by ShotIQ AI.',
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
          'Analyze Your First Shot',
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
            'Upload a video or record your shot to get your first AI shooting analysis.',
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
