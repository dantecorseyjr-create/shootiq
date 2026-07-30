import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/widgets/settings/settings_subpage_scaffold.dart';

class ReportProblemPage extends StatefulWidget {
  const ReportProblemPage({super.key});

  @override
  State<ReportProblemPage> createState() => _ReportProblemPageState();
}

class _ReportProblemPageState extends State<ReportProblemPage> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  static const _categories = [
    'Incorrect AI Analysis',
    'Crash',
    'Performance',
    'Video Issue',
    'Subscription',
    'Other',
  ];

  String _category = _categories.first;
  bool _submitting = false;
  String? _screenshotLabel;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshotPlaceholder() async {
    // TODO(backend): integrate image_picker and upload screenshot with the report.
    setState(() => _screenshotLabel = 'Screenshot attached (local placeholder)');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Screenshot picker will upload with the report once backend support is live.',
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      // TODO(backend): submit problem report + optional screenshot to ShootIQ API.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report saved. Thank you for helping improve ShootIQ.'),
        ),
      );
      _descriptionController.clear();
      setState(() => _screenshotLabel = null);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubpageScaffold(
      title: 'Report a Problem',
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            const Text(
              'Describe what went wrong. Include steps to reproduce when possible.',
              style: TextStyle(color: ShootIQTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            SettingsInfoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    controller: _descriptionController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().length < 12)
                            ? 'Please describe the issue'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _pickScreenshotPlaceholder,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(_screenshotLabel ?? 'Add screenshot (optional)'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SettingsPrimaryButton(
              label: 'Submit Report',
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
