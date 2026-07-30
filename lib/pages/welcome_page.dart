import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/widgets/premium/premium_widgets.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 5,
              child: Image.asset(
                'assets/images/premium.png',
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: double.infinity,
                    color: PremiumColors.cardBackground,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.sports_basketball_rounded,
                      size: 88,
                      color: ShootIQTheme.buttonBlue,
                    ),
                  );
                },
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'ShootIQ',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: PremiumColors.title,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'AI Basketball Shooting Coach',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                color: Colors.black54,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: () => context.go(AppRoutes.signup),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: ShootIQTheme.buttonBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  side: const BorderSide(
                                    color: ShootIQTheme.redBorder,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.email_outlined, size: 22),
                                    SizedBox(width: 8),
                                    Text(
                                      'Continue with Email',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextButton(
                              onPressed: () => context.go(AppRoutes.login),
                              style: TextButton.styleFrom(
                                foregroundColor: PremiumColors.title,
                              ),
                              child: const Text.rich(
                                TextSpan(
                                  style: TextStyle(fontSize: 15),
                                  children: [
                                    TextSpan(
                                      text: 'Already have an account? ',
                                      style: TextStyle(
                                        color: PremiumColors.subtitle,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'Log In',
                                      style: TextStyle(
                                        color: ShootIQTheme.buttonBlue,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
