import 'package:flutter/material.dart';
import 'package:shootiq/config/supabase_config.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: true,
        // Matches android:host / deep-link host for shootiq://login-callback/
        // so OAuth return URLs restore the persisted session automatically.
      ),
    ),
    OnboardingService.init(),
  ]);

  AuthService.initAuthListener();

  runApp(const ShootIQApp());
}

class ShootIQApp extends StatelessWidget {
  const ShootIQApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ShootIQ',
      debugShowCheckedModeBanner: false,
      theme: ShootIQTheme.lightTheme,
      darkTheme: ShootIQTheme.lightTheme,
      routerConfig: AppRouter.create(),
    );
  }
}
