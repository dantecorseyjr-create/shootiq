import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/local_shot_history_store.dart';
import 'package:shootiq/services/profile_service.dart';
import 'package:shootiq/services/subscription_service.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  bool _acknowledged = false;
  bool _busy = false;
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_confirmController.text.trim().toUpperCase() != 'DELETE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type DELETE to confirm.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final user = AuthService.currentUser;
      if (user == null) {
        throw StateError('You must be signed in.');
      }

      // Clear local app data first.
      final shots = await LocalShotHistoryStore.loadForUser(user.id);
      for (final shot in shots) {
        await LocalShotHistoryStore.removeById(shot.id);
      }
      await SubscriptionService.clearSubscription();
      ProfileService.clear();

      // TODO(backend): call a secure Supabase Edge Function / Admin API to
      // permanently delete auth.users + player_profiles for this userId.
      // Direct client-side auth.admin.deleteUser is not available with anon key.
      try {
        await Supabase.instance.client.from('player_profiles').delete().eq(
              'user_id',
              user.id,
            );
      } catch (_) {
        // Best-effort profile row cleanup.
      }

      await AuthService.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Account signed out and local data cleared. Server account deletion will complete once backend delete is enabled.',
          ),
        ),
      );
      context.go(AppRoutes.home);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete account: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Delete Account',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          SettingsInfoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'This will permanently remove',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ShootIQTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  '• Your ShootIQ account login\n'
                  '• Player profile information\n'
                  '• Cloud subscription entitlement records (when backend delete is enabled)\n'
                  '• On-device shot history JSON stored by ShootIQ',
                  style: TextStyle(
                    color: ShootIQTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Videos stored locally on your device are NOT automatically deleted. '
                  'Remove camera-roll / Documents media yourself if you want them gone.',
                  style: TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: _acknowledged,
            onChanged: _busy
                ? null
                : (value) => setState(() => _acknowledged = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I understand this cannot be undone',
              style: TextStyle(
                color: ShootIQTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Type DELETE to confirm',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: !_acknowledged || _busy ? null : _delete,
              style: FilledButton.styleFrom(
                backgroundColor: ShootIQTheme.errorRed,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    ShootIQTheme.errorRed.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Delete Account',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            // TODO(backend): harden with server-side auth user deletion + cascade.
            'TODO: finish authenticated server account deletion endpoint.',
            textAlign: TextAlign.center,
            style: TextStyle(color: ShootIQTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
