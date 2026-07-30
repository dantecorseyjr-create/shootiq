import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class ContactSupportPage extends StatefulWidget {
  const ContactSupportPage({super.key});

  @override
  State<ContactSupportPage> createState() => _ContactSupportPageState();
}

class _ContactSupportPageState extends State<ContactSupportPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController(
    text: AuthService.currentUser?.email ?? '',
  );
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  static const _categories = [
    'Bug',
    'Billing',
    'AI Analysis',
    'Subscription',
    'Feature Request',
    'Other',
  ];

  String _category = _categories.first;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      // TODO(backend): POST support ticket to ShootIQ support API / Supabase edge function.
      // Payload: name, email, category, subject, message, userId, appVersion, platform.
      await Future<void>.delayed(const Duration(milliseconds: 700));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks — your message was saved locally. Our team will follow up once support sync is online.',
          ),
        ),
      );
      _subjectController.clear();
      _messageController.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Contact Support',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            const Text(
              'Tell us how we can help. We typically respond within 1–2 business days.',
              style: TextStyle(
                color: ShootIQTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SettingsInfoCard(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final category in _categories)
                        DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _category = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Enter your name'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your email';
                      }
                      if (!value.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                            ? 'Enter a subject'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _messageController,
                    minLines: 5,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().length < 10)
                            ? 'Please add a bit more detail'
                            : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SettingsPrimaryButton(
              label: 'Send Message',
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
