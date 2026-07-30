import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/pages/ai_analyzer_page.dart';
import 'package:shootiq/pages/ai_coach_page.dart';
import 'package:shootiq/pages/analyze_page.dart';
import 'package:shootiq/pages/analyze_shot_page.dart';
import 'package:shootiq/pages/camera_capture_page.dart';
import 'package:shootiq/pages/camera_page.dart';
import 'package:shootiq/pages/confidence_page.dart';
import 'package:shootiq/pages/drills_page.dart';
import 'package:shootiq/pages/edit_profile_page.dart';
import 'package:shootiq/pages/forgot_password_page.dart';
import 'package:shootiq/pages/goal_page.dart';
import 'package:shootiq/pages/help_start_page.dart';
import 'package:shootiq/pages/history_page.dart';
import 'package:shootiq/pages/home_page.dart';
import 'package:shootiq/pages/improve_page.dart';
import 'package:shootiq/pages/login_page.dart';
import 'package:shootiq/pages/page2_page.dart';
import 'package:shootiq/pages/player_setup_page.dart';
import 'package:shootiq/pages/premium_page.dart';
import 'package:shootiq/pages/processing_page.dart';
import 'package:shootiq/pages/profile_page.dart';
import 'package:shootiq/pages/progress_page.dart';
import 'package:shootiq/pages/record_video_page.dart';
import 'package:shootiq/pages/movement_detail_page.dart';
import 'package:shootiq/pages/results_page.dart';
import 'package:shootiq/pages/session_compare_page.dart';
import 'package:shootiq/models/movement_issue.dart';
import 'package:shootiq/models/shot_coach_context.dart';
import 'package:shootiq/pages/settings_page.dart';
import 'package:shootiq/pages/privacy_policy_page.dart';
import 'package:shootiq/pages/terms_of_service_page.dart';
import 'package:shootiq/pages/help_center_page.dart';
import 'package:shootiq/pages/contact_support_page.dart';
import 'package:shootiq/pages/report_problem_page.dart';
import 'package:shootiq/pages/rate_shootiq_page.dart';
import 'package:shootiq/pages/download_my_data_page.dart';
import 'package:shootiq/pages/export_shot_history_page.dart';
import 'package:shootiq/pages/manage_subscription_page.dart';
import 'package:shootiq/pages/restore_purchases_page.dart';
import 'package:shootiq/pages/delete_account_page.dart';
import 'package:shootiq/pages/about_page.dart';
import 'package:shootiq/pages/shot_ai_chat_page.dart';
import 'package:shootiq/pages/shot_capture_page.dart';
import 'package:shootiq/pages/shot_upload_page.dart';
import 'package:shootiq/pages/signup_page.dart';
import 'package:shootiq/pages/subscription_page.dart';
import 'package:shootiq/pages/upload_page.dart';
import 'package:shootiq/pages/video_preview_page.dart';
import 'package:shootiq/pages/video_upload_page.dart';
import 'package:shootiq/pages/welcome_back_page.dart';
import 'package:shootiq/pages/welcome_page.dart';
import 'dart:io';

import 'package:shootiq/models/shot_analysis.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/onboarding_service.dart';
import 'package:shootiq/services/pending_analysis_store.dart';
import 'package:shootiq/services/subscription_service.dart';
import 'package:shootiq/widgets/main_shell.dart';

/// Centralized route paths for ShootIQ.
class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const premium = '/premium';
  static const page2 = '/page2';
  static const analyzeShot = '/analyze-shot';
  static const captureShot = '/capture-shot';
  static const processing = '/processing';
  static const subscription = '/subscription';
  static const camera = '/camera';
  static const cameraCapture = '/camera-capture';
  static const videoPreview = '/video-preview';
  static const videoUpload = '/video-upload';
  static const uploadShot = '/upload-shot';
  static const goal = '/goal';
  static const helpStart = '/help-start';
  static const confidence = '/confidence';
  static const improve = '/improve';
  static const analyzer = '/analyzer';
  static const dashboard = '/dashboard';
  static const progress = '/progress';
  static const analyze = '/analyze';
  static const history = '/history';
  static const sessionCompare = '/session-compare';
  static const drills = '/drills';
  static const profile = '/profile';
  static const settings = '/settings';
  static const editProfile = '/edit-profile';
  static const privacyPolicy = '/privacy-policy';
  static const termsOfService = '/terms-of-service';
  static const helpCenter = '/help-center';
  static const contactSupport = '/contact-support';
  static const reportProblem = '/report-problem';
  static const rateShootIq = '/rate-shootiq';
  static const downloadMyData = '/download-my-data';
  static const exportShotHistory = '/export-shot-history';
  static const manageSubscription = '/manage-subscription';
  static const restorePurchases = '/restore-purchases';
  static const deleteAccount = '/delete-account';
  static const about = '/about';
  static const aiCoach = '/ai-coach';
  static const signup = '/signup';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const playerSetup = '/player-setup';
  static const record = '/record';
  static const upload = '/upload';
  static const results = '/results';
  static const movementDetail = '/movement-detail';
  static const shotAiChat = '/shot-ai-chat';
  static const welcomeBack = '/welcome-back';
}

/// GoRouter configuration with auth + onboarding gates.
class AppRouter {
  AppRouter._();

  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static const _publicAuthRoutes = {
    AppRoutes.home,
    AppRoutes.login,
    AppRoutes.signup,
    AppRoutes.forgotPassword,
    AppRoutes.premium,
    AppRoutes.subscription,
  };

  /// First-launch marketing/onboarding screens.
  /// Premium/Subscription stay reachable after onboarding (analyze paywall).
  static const _firstLaunchOnlyRoutes = {
    AppRoutes.home,
    AppRoutes.page2,
    AppRoutes.playerSetup,
    AppRoutes.goal,
    AppRoutes.helpStart,
    AppRoutes.confidence,
  };

  static const _appShellRoutes = {
    AppRoutes.dashboard,
    AppRoutes.progress,
    AppRoutes.analyze,
    AppRoutes.history,
    AppRoutes.sessionCompare,
    AppRoutes.results,
    AppRoutes.movementDetail,
    AppRoutes.shotAiChat,
    AppRoutes.drills,
    AppRoutes.profile,
    AppRoutes.settings,
    AppRoutes.editProfile,
    AppRoutes.privacyPolicy,
    AppRoutes.termsOfService,
    AppRoutes.helpCenter,
    AppRoutes.contactSupport,
    AppRoutes.reportProblem,
    AppRoutes.rateShootIq,
    AppRoutes.downloadMyData,
    AppRoutes.exportShotHistory,
    AppRoutes.manageSubscription,
    AppRoutes.restorePurchases,
    AppRoutes.deleteAccount,
    AppRoutes.about,
    AppRoutes.aiCoach,
    AppRoutes.record,
    AppRoutes.upload,
    AppRoutes.videoUpload,
  };

  static String _initialLocation() {
    if (!AuthService.isAuthenticated) {
      return AppRoutes.home;
    }
    if (OnboardingService.hasCompletedOnboarding) {
      return AppRoutes.dashboard;
    }
    // Do not force Premium after signup — let users explore via setup/goals first.
    if (!OnboardingService.hasCompletedPlayerSetup) {
      return AppRoutes.playerSetup;
    }
    return AppRoutes.goal;
  }

  static Future<String?> _redirect(
    BuildContext context,
    GoRouterState state,
  ) async {
    final location = state.matchedLocation;
    final loggedIn = AuthService.isAuthenticated;
    final onboarded = OnboardingService.hasCompletedOnboarding;
    final playerSetupDone = OnboardingService.hasCompletedPlayerSetup;

    // Not logged in → Welcome / auth screens only.
    if (!loggedIn) {
      if (_publicAuthRoutes.contains(location)) return null;
      // Allow light marketing/onboarding preview before account creation.
      if (location == AppRoutes.page2) return null;
      return AppRoutes.home;
    }

    // Real shot analysis (camera/upload) requires an active subscription.
    // Free users may explore the rest of the app without hitting this gate.
    if (SubscriptionService.isAnalysisLockedRoute(location)) {
      final allowed = await SubscriptionService.checkAnalysisAccess();
      if (!allowed) {
        return '${AppRoutes.premium}?next=${Uri.encodeComponent(location)}';
      }
    }

    // Logged in + finished onboarding → Home (skip onboarding entry points).
    if (onboarded) {
      if (_firstLaunchOnlyRoutes.contains(location) ||
          location == AppRoutes.login ||
          location == AppRoutes.signup ||
          location == AppRoutes.forgotPassword) {
        return AppRoutes.dashboard;
      }
      return null;
    }

    // Logged in + new user still onboarding → Player Setup first (not Premium).
    if (!playerSetupDone) {
      if (location == AppRoutes.playerSetup ||
          location == AppRoutes.premium ||
          location == AppRoutes.subscription) {
        return null;
      }
      // Keep auth screens away once session exists.
      if (location == AppRoutes.login ||
          location == AppRoutes.signup ||
          location == AppRoutes.forgotPassword ||
          location == AppRoutes.home) {
        return AppRoutes.playerSetup;
      }
      if (_appShellRoutes.contains(location)) {
        return AppRoutes.playerSetup;
      }
      return null;
    }

    // Player setup done, onboarding incomplete → keep them in onboarding.
    // Premium/Subscription remain optional (not forced).
    if (location == AppRoutes.login ||
        location == AppRoutes.signup ||
        location == AppRoutes.forgotPassword ||
        location == AppRoutes.home ||
        location == AppRoutes.playerSetup) {
      return AppRoutes.goal;
    }
    if (_appShellRoutes.contains(location)) {
      return AppRoutes.goal;
    }

    return null;
  }

  static GoRouter create() {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: _initialLocation(),
      refreshListenable: AuthService.authListenable,
      redirect: _redirect,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const WelcomePage(),
        ),
        GoRoute(
          path: AppRoutes.welcomeBack,
          builder: (context, state) => const WelcomeBackPage(),
        ),
        GoRoute(
          path: AppRoutes.premium,
          builder: (context, state) => const PremiumPage(),
        ),
        GoRoute(
          path: AppRoutes.page2,
          builder: (context, state) => const Page2Page(),
        ),
        GoRoute(
          path: AppRoutes.analyzeShot,
          builder: (context, state) => const AnalyzeShotPage(),
        ),
        GoRoute(
          path: AppRoutes.captureShot,
          builder: (context, state) {
            final openGallery = state.extra as bool? ?? false;
            return ShotCapturePage(openGalleryOnLoad: openGallery);
          },
        ),
        GoRoute(
          path: AppRoutes.processing,
          builder: (context, state) {
            final extra = state.extra;
            if (extra is ShotAnalysis) {
              return ProcessingPage(analysis: extra);
            }
            // Recover stashed path when paywall/redirect dropped `extra: File`.
            final video = PendingAnalysisStore.resolveVideo(extra);
            if (video != null) {
              return ProcessingPage(videoFile: video);
            }
            return const ProcessingPage();
          },
        ),
        GoRoute(
          path: AppRoutes.subscription,
          builder: (context, state) {
            final next = state.uri.queryParameters['next'];
            return SubscriptionPage(nextRoute: next);
          },
        ),
        GoRoute(
          path: AppRoutes.camera,
          builder: (context, state) => const CameraPage(),
        ),
        GoRoute(
          path: AppRoutes.cameraCapture,
          builder: (context, state) => const CameraCapturePage(),
        ),
        GoRoute(
          path: AppRoutes.videoPreview,
          builder: (context, state) {
            final extra = state.extra;
            final path = extra is String
                ? extra
                : extra is File
                    ? extra.path
                    : null;
            return VideoPreviewPage(videoPath: path);
          },
        ),
        GoRoute(
          path: AppRoutes.videoUpload,
          builder: (context, state) => const VideoUploadPage(),
        ),
        GoRoute(
          path: AppRoutes.uploadShot,
          builder: (context, state) => const ShotUploadPage(),
        ),
        GoRoute(
          path: AppRoutes.goal,
          builder: (context, state) => const GoalPage(),
        ),
        GoRoute(
          path: AppRoutes.helpStart,
          builder: (context, state) => const HelpStartPage(),
        ),
        GoRoute(
          path: AppRoutes.confidence,
          builder: (context, state) => const ConfidencePage(),
        ),
        GoRoute(
          path: AppRoutes.improve,
          builder: (context, state) => const ImprovePage(),
        ),
        GoRoute(
          path: AppRoutes.analyzer,
          builder: (context, state) => const AiAnalyzerPage(),
        ),
        GoRoute(
          path: AppRoutes.signup,
          builder: (context, state) => const SignupPage(),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: AppRoutes.forgotPassword,
          builder: (context, state) => const ForgotPasswordPage(),
        ),
        GoRoute(
          path: AppRoutes.playerSetup,
          builder: (context, state) => const PlayerSetupPage(),
        ),
        ShellRoute(
          builder: (context, state, child) => MainShell(child: child),
          routes: [
            GoRoute(
              path: AppRoutes.dashboard,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: HomePage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.progress,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ProgressPage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.analyze,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: AnalyzePage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.history,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: HistoryPage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.sessionCompare,
              pageBuilder: (context, state) {
                final extra = state.extra;
                String? leftId;
                String? rightId;
                if (extra is Map) {
                  leftId = extra['leftId'] as String? ??
                      extra['left_id'] as String?;
                  rightId = extra['rightId'] as String? ??
                      extra['right_id'] as String?;
                }
                return NoTransitionPage(
                  child: SessionComparePage(
                    initialLeftId: leftId,
                    initialRightId: rightId,
                  ),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.results,
              pageBuilder: (context, state) {
                final extra = state.extra;
                if (extra is Map<String, dynamic>) {
                  return NoTransitionPage(
                    child: ResultsPage(results: extra),
                  );
                }
                if (extra is Map) {
                  return NoTransitionPage(
                    child: ResultsPage(
                      results: Map<String, dynamic>.from(extra),
                    ),
                  );
                }
                final analysis = extra as ShotAnalysis?;
                return NoTransitionPage(
                  child: ResultsPage(analysis: analysis),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.movementDetail,
              builder: (context, state) {
                final args = MovementDetailArgs.fromExtra(state.extra);
                if (args == null) {
                  return const Scaffold(
                    backgroundColor: ShootIQTheme.background,
                    body: Center(
                      child: Text(
                        'Movement details unavailable',
                        style: TextStyle(color: ShootIQTheme.textSecondary),
                      ),
                    ),
                  );
                }
                return MovementDetailPage(
                  issue: args.issue,
                  networkUrl: args.networkUrl,
                  fallbackUrls: args.fallbackUrls,
                  file: args.file,
                  preferLocalFile: args.preferLocalFile,
                );
              },
            ),
            GoRoute(
              path: AppRoutes.shotAiChat,
              builder: (context, state) {
                final coachContext = ShotCoachContext.fromExtra(state.extra);
                if (coachContext == null) {
                  return const Scaffold(
                    backgroundColor: ShootIQTheme.background,
                    body: Center(
                      child: Text(
                        'Shot analysis unavailable',
                        style: TextStyle(color: ShootIQTheme.textSecondary),
                      ),
                    ),
                  );
                }
                return ShotAiChatPage(contextData: coachContext);
              },
            ),
            GoRoute(
              path: AppRoutes.drills,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: DrillsPage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.profile,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ProfilePage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.settings,
              pageBuilder: (context, state) {
                final fromQuery = SettingsSection.tryParse(
                  state.uri.queryParameters['section'],
                );
                final fromExtra = state.extra is SettingsSection
                    ? state.extra as SettingsSection
                    : null;
                return NoTransitionPage(
                  child: SettingsPage(
                    initialSection: fromExtra ?? fromQuery,
                  ),
                );
              },
            ),
            GoRoute(
              path: AppRoutes.editProfile,
              builder: (context, state) => const EditProfilePage(),
            ),
            GoRoute(
              path: AppRoutes.privacyPolicy,
              builder: (context, state) => const PrivacyPolicyPage(),
            ),
            GoRoute(
              path: AppRoutes.termsOfService,
              builder: (context, state) => const TermsOfServicePage(),
            ),
            GoRoute(
              path: AppRoutes.helpCenter,
              builder: (context, state) => const HelpCenterPage(),
            ),
            GoRoute(
              path: AppRoutes.contactSupport,
              builder: (context, state) => const ContactSupportPage(),
            ),
            GoRoute(
              path: AppRoutes.reportProblem,
              builder: (context, state) => const ReportProblemPage(),
            ),
            GoRoute(
              path: AppRoutes.rateShootIq,
              builder: (context, state) => const RateShootIqPage(),
            ),
            GoRoute(
              path: AppRoutes.downloadMyData,
              builder: (context, state) => const DownloadMyDataPage(),
            ),
            GoRoute(
              path: AppRoutes.exportShotHistory,
              builder: (context, state) => const ExportShotHistoryPage(),
            ),
            GoRoute(
              path: AppRoutes.manageSubscription,
              builder: (context, state) => const ManageSubscriptionPage(),
            ),
            GoRoute(
              path: AppRoutes.restorePurchases,
              builder: (context, state) => const RestorePurchasesPage(),
            ),
            GoRoute(
              path: AppRoutes.deleteAccount,
              builder: (context, state) => const DeleteAccountPage(),
            ),
            GoRoute(
              path: AppRoutes.about,
              builder: (context, state) => const AboutPage(),
            ),
            GoRoute(
              path: AppRoutes.aiCoach,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: AiCoachPage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.record,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: RecordVideoPage(),
              ),
            ),
            GoRoute(
              path: AppRoutes.upload,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: UploadPage(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
