import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/player_profile.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/auth_service.dart';
import 'package:shootiq/services/profile_service.dart';

const _positions = [
  'Point Guard',
  'Shooting Guard',
  'Small Forward',
  'Power Forward',
  'Center',
];

const _dominantHands = ['Left', 'Right'];

const _skillLevels = [
  'Beginner',
  'Intermediate',
  'Advanced',
  'Elite',
];

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _favoriteTeamController = TextEditingController();
  final _bioController = TextEditingController();
  final _imagePicker = ImagePicker();

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;
  String? _email;
  String? _existingPhotoUrl;
  File? _pickedPhoto;

  int _heightFeet = 6;
  int _heightInches = 0;
  int _weightLbs = 180;
  int _age = 18;
  int _experienceYears = 0;

  String? _dominantHand;
  String? _position;
  String? _skillLevel;

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
    _load();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _favoriteTeamController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await ProfileService.loadProfile();
      final parsedHeight = _parseHeight(profile.height);
      if (!mounted) return;
      setState(() {
        _email = AuthService.currentUser?.email ?? '';
        _firstNameController.text = profile.firstName;
        _lastNameController.text = profile.lastName;
        _usernameController.text = profile.username;
        _favoriteTeamController.text = profile.favoriteTeam ?? '';
        _bioController.text = profile.bio ?? '';
        _existingPhotoUrl = profile.photoUrl;
        _heightFeet = parsedHeight.$1;
        _heightInches = parsedHeight.$2;
        _weightLbs = profile.weight ?? 180;
        _age = profile.age ?? 18;
        _experienceYears = profile.experience ?? 0;
        _dominantHand = profile.dominantHand;
        _position = profile.position;
        _skillLevel = profile.skillLevel == 'Competitive'
            ? 'Elite'
            : profile.skillLevel;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Could not load your profile.';
      });
    }
  }

  static (int, int) _parseHeight(String? raw) {
    if (raw == null || raw.trim().isEmpty) return (6, 0);
    final match = RegExp(r"(\d+)\s*'\s*(\d+)").firstMatch(raw);
    if (match != null) {
      final feet = int.tryParse(match.group(1)!) ?? 6;
      final inches = int.tryParse(match.group(2)!) ?? 0;
      return (feet.clamp(4, 7), inches.clamp(0, 11));
    }
    final feetOnly = RegExp(r"(\d+)\s*'").firstMatch(raw);
    if (feetOnly != null) {
      return ((int.tryParse(feetOnly.group(1)!) ?? 6).clamp(4, 7), 0);
    }
    return (6, 0);
  }

  String get _heightLabel => "$_heightFeet'$_heightInches\"";

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: ShootIQTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ShootIQTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Change Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: ShootIQTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_outlined,
                    color: ShootIQTheme.basketballOrange,
                  ),
                  title: const Text(
                    'Choose from Gallery',
                    style: TextStyle(color: ShootIQTheme.textPrimary),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_camera_outlined,
                    color: ShootIQTheme.basketballOrange,
                  ),
                  title: const Text(
                    'Take a Photo',
                    style: TextStyle(color: ShootIQTheme.textPrimary),
                  ),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;
      setState(() => _pickedPhoto = File(picked.path));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not update photo. Check permissions.');
    }
  }

  Future<void> _pickHeight() async {
    var feet = _heightFeet;
    var inches = _heightInches;
    await _showWheelPicker(
      title: 'Height',
      child: Row(
        children: [
          Expanded(
            child: CupertinoPicker(
              scrollController:
                  FixedExtentScrollController(initialItem: feet - 4),
              itemExtent: 40,
              onSelectedItemChanged: (index) => feet = index + 4,
              children: [
                for (var f = 4; f <= 7; f++)
                  Center(
                    child: Text(
                      "$f'",
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: CupertinoPicker(
              scrollController:
                  FixedExtentScrollController(initialItem: inches),
              itemExtent: 40,
              onSelectedItemChanged: (index) => inches = index,
              children: [
                for (var i = 0; i <= 11; i++)
                  Center(
                    child: Text(
                      '$i"',
                      style: const TextStyle(
                        color: ShootIQTheme.textPrimary,
                        fontSize: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      onDone: () => setState(() {
        _heightFeet = feet;
        _heightInches = inches;
      }),
    );
  }

  Future<void> _pickWeight() async {
    var value = _weightLbs.clamp(80, 350);
    await _showWheelPicker(
      title: 'Weight',
      child: CupertinoPicker(
        scrollController:
            FixedExtentScrollController(initialItem: value - 80),
        itemExtent: 40,
        onSelectedItemChanged: (index) => value = index + 80,
        children: [
          for (var w = 80; w <= 350; w++)
            Center(
              child: Text(
                '$w lbs',
                style: const TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 20,
                ),
              ),
            ),
        ],
      ),
      onDone: () => setState(() => _weightLbs = value),
    );
  }

  Future<void> _pickAge() async {
    var value = _age.clamp(8, 80);
    await _showWheelPicker(
      title: 'Age',
      child: CupertinoPicker(
        scrollController:
            FixedExtentScrollController(initialItem: value - 8),
        itemExtent: 40,
        onSelectedItemChanged: (index) => value = index + 8,
        children: [
          for (var a = 8; a <= 80; a++)
            Center(
              child: Text(
                '$a',
                style: const TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 20,
                ),
              ),
            ),
        ],
      ),
      onDone: () => setState(() => _age = value),
    );
  }

  Future<void> _pickExperience() async {
    var value = _experienceYears.clamp(0, 40);
    await _showWheelPicker(
      title: 'Years of Experience',
      child: CupertinoPicker(
        scrollController: FixedExtentScrollController(initialItem: value),
        itemExtent: 40,
        onSelectedItemChanged: (index) => value = index,
        children: [
          for (var y = 0; y <= 40; y++)
            Center(
              child: Text(
                y == 1 ? '1 year' : '$y years',
                style: const TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 20,
                ),
              ),
            ),
        ],
      ),
      onDone: () => setState(() => _experienceYears = value),
    );
  }

  Future<void> _showWheelPicker({
    required String title,
    required Widget child,
    required VoidCallback onDone,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: ShootIQTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: ShootIQTheme.textSecondary),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: ShootIQTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          onDone();
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: ShootIQTheme.basketballOrange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;

    if (_dominantHand == null || _position == null || _skillLevel == null) {
      setState(() {
        _errorMessage =
            'Select dominant hand, primary position, and skill level.';
      });
      return;
    }

    final user = AuthService.currentUser;
    if (user == null) {
      setState(() => _errorMessage = 'You must be signed in to save.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final draft = PlayerProfile(
      id: ProfileService.current?.id,
      userId: user.id,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      username: _usernameController.text.trim(),
      height: _heightLabel,
      weight: _weightLbs,
      age: _age,
      dominantHand: _dominantHand,
      position: _position,
      skillLevel: _skillLevel,
      experience: _experienceYears,
      favoriteTeam: _favoriteTeamController.text.trim().isEmpty
          ? null
          : _favoriteTeamController.text.trim(),
      bio: _bioController.text.trim().isEmpty
          ? null
          : _bioController.text.trim(),
      photoUrl: _existingPhotoUrl,
    );

    try {
      await ProfileService.saveProfile(draft, photoFile: _pickedPhoto);
      if (!mounted) return;
      context.go(AppRoutes.profile);
    } catch (_) {
      // Local state is still updated by ProfileService for instant Profile UI.
      if (!mounted) return;
      if (ProfileService.current != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile updated on this device. Cloud sync may need the player_profiles migration.',
            ),
            backgroundColor: ShootIQTheme.surfaceElevated,
          ),
        );
        context.go(AppRoutes.profile);
      } else {
        setState(() {
          _errorMessage = 'Could not save your profile. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _EditProfileAppBar(
                  onBack: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.settings);
                    }
                  },
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: ShootIQTheme.basketballOrange,
                        ),
                      )
                    : Form(
                        key: _formKey,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            20,
                            24,
                            32 + MediaQuery.viewInsetsOf(context).bottom,
                          ),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          children: [
                            if (_errorMessage != null) ...[
                              _ErrorBanner(message: _errorMessage!),
                              const SizedBox(height: 16),
                            ],
                            _PhotoSection(
                              photoFile: _pickedPhoto,
                              photoUrl: _existingPhotoUrl,
                              onChangePhoto: _saving ? null : _pickPhoto,
                            ),
                            const SizedBox(height: 28),
                            _SectionCard(
                              children: [
                                _LabeledField(
                                  label: 'First Name',
                                  child: TextFormField(
                                    controller: _firstNameController,
                                    enabled: !_saving,
                                    textInputAction: TextInputAction.next,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: _fieldStyle,
                                    cursorColor: ShootIQTheme.basketballOrange,
                                    decoration: _inputDecoration(
                                      hint: 'First name',
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Enter your first name';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _LabeledField(
                                  label: 'Last Name',
                                  child: TextFormField(
                                    controller: _lastNameController,
                                    enabled: !_saving,
                                    textInputAction: TextInputAction.next,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: _fieldStyle,
                                    cursorColor: ShootIQTheme.basketballOrange,
                                    decoration: _inputDecoration(
                                      hint: 'Last name',
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Enter your last name';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _LabeledField(
                                  label: 'Username',
                                  child: TextFormField(
                                    controller: _usernameController,
                                    enabled: !_saving,
                                    textInputAction: TextInputAction.next,
                                    style: _fieldStyle,
                                    cursorColor: ShootIQTheme.basketballOrange,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[a-zA-Z0-9._]'),
                                      ),
                                    ],
                                    decoration: _inputDecoration(
                                      hint: 'username',
                                      prefixText: '@',
                                    ),
                                    validator: (value) {
                                      final trimmed = value?.trim() ?? '';
                                      if (trimmed.isEmpty) {
                                        return 'Enter a username';
                                      }
                                      if (trimmed.length < 3) {
                                        return 'Username must be at least 3 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _LabeledField(
                                  label: 'Email Address',
                                  child: TextFormField(
                                    initialValue: _email ?? '',
                                    enabled: false,
                                    style: _fieldStyle.copyWith(
                                      color: ShootIQTheme.textSecondary,
                                    ),
                                    decoration: _inputDecoration(
                                      hint: 'email@example.com',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              children: [
                                _PickerTile(
                                  label: 'Height',
                                  value: _heightLabel,
                                  icon: Icons.height_rounded,
                                  onTap: _saving ? null : _pickHeight,
                                ),
                                const _CardDivider(),
                                _PickerTile(
                                  label: 'Weight',
                                  value: '$_weightLbs lbs',
                                  icon: Icons.monitor_weight_outlined,
                                  onTap: _saving ? null : _pickWeight,
                                ),
                                const _CardDivider(),
                                _PickerTile(
                                  label: 'Age',
                                  value: '$_age',
                                  icon: Icons.cake_outlined,
                                  onTap: _saving ? null : _pickAge,
                                ),
                                const _CardDivider(),
                                _PickerTile(
                                  label: 'Years of Experience',
                                  value: _experienceYears == 1
                                      ? '1 year'
                                      : '$_experienceYears years',
                                  icon: Icons.timeline_rounded,
                                  onTap: _saving ? null : _pickExperience,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              children: [
                                const _ChipLabel(text: 'Dominant Hand'),
                                const SizedBox(height: 10),
                                _OptionChips(
                                  options: _dominantHands,
                                  selected: _dominantHand,
                                  onSelected: _saving
                                      ? null
                                      : (value) => setState(
                                            () => _dominantHand = value,
                                          ),
                                ),
                                const SizedBox(height: 22),
                                const _ChipLabel(text: 'Primary Position'),
                                const SizedBox(height: 10),
                                _OptionChips(
                                  options: _positions,
                                  selected: _position,
                                  onSelected: _saving
                                      ? null
                                      : (value) =>
                                          setState(() => _position = value),
                                ),
                                const SizedBox(height: 22),
                                const _ChipLabel(text: 'Skill Level'),
                                const SizedBox(height: 10),
                                _OptionChips(
                                  options: _skillLevels,
                                  selected: _skillLevel,
                                  onSelected: _saving
                                      ? null
                                      : (value) =>
                                          setState(() => _skillLevel = value),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _SectionCard(
                              children: [
                                _LabeledField(
                                  label: 'Favorite Team (optional)',
                                  child: TextFormField(
                                    controller: _favoriteTeamController,
                                    enabled: !_saving,
                                    textInputAction: TextInputAction.next,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    style: _fieldStyle,
                                    cursorColor: ShootIQTheme.basketballOrange,
                                    decoration: _inputDecoration(
                                      hint: 'e.g. Boston Celtics',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _LabeledField(
                                  label: 'Bio (optional)',
                                  child: TextFormField(
                                    controller: _bioController,
                                    enabled: !_saving,
                                    maxLength: 200,
                                    maxLines: 4,
                                    style: _fieldStyle,
                                    cursorColor: ShootIQTheme.basketballOrange,
                                    decoration: _inputDecoration(
                                      hint: 'Tell us about your game...',
                                    ).copyWith(
                                      counterStyle: const TextStyle(
                                        color: ShootIQTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: FilledButton(
                                onPressed: _saving ? null : _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: ShootIQTheme.buttonBlue,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: ShootIQTheme
                                      .buttonBlue
                                      .withValues(alpha: 0.5),
                                  elevation: 0,
                                  side: const BorderSide(
                                    color: ShootIQTheme.redBorder,
                                    width: 2,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Save Changes'),
                              ),
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

const _fieldStyle = TextStyle(
  color: ShootIQTheme.textPrimary,
  fontSize: 16,
);

InputDecoration _inputDecoration({String? hint, String? prefixText}) {
  return InputDecoration(
    hintText: hint,
    prefixText: prefixText,
    prefixStyle: const TextStyle(
      color: ShootIQTheme.textSecondary,
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
    hintStyle: TextStyle(
      color: ShootIQTheme.textSecondary.withValues(alpha: 0.7),
    ),
    filled: true,
    fillColor: ShootIQTheme.surfaceElevated,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: ShootIQTheme.cardBorder),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(
        color: ShootIQTheme.basketballOrange,
        width: 1.4,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: ShootIQTheme.errorRed),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: ShootIQTheme.errorRed, width: 1.4),
    ),
  );
}

class _EditProfileAppBar extends StatelessWidget {
  const _EditProfileAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: ShootIQTheme.surfaceElevated,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: ShootIQTheme.textPrimary,
              ),
            ),
          ),
        ),
        const Expanded(
          child: Text(
            'Edit Profile',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ShootIQTheme.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}

class _PhotoSection extends StatelessWidget {
  const _PhotoSection({
    required this.photoFile,
    required this.photoUrl,
    required this.onChangePhoto,
  });

  final File? photoFile;
  final String? photoUrl;
  final VoidCallback? onChangePhoto;

  @override
  Widget build(BuildContext context) {
    ImageProvider? image;
    if (photoFile != null) {
      image = FileImage(photoFile!);
    } else if (photoUrl != null && photoUrl!.isNotEmpty) {
      image = NetworkImage(photoUrl!);
    }

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: image == null
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          ShootIQTheme.basketballOrange,
                          ShootIQTheme.basketballOrangeLight,
                        ],
                      )
                    : null,
                image: image == null
                    ? null
                    : DecorationImage(image: image, fit: BoxFit.cover),
                boxShadow: [
                  BoxShadow(
                    color:
                        ShootIQTheme.basketballOrange.withValues(alpha: 0.3),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: ShootIQTheme.cardBorder,
                  width: 3,
                ),
              ),
              child: image == null
                  ? const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 60,
                    )
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: ShootIQTheme.basketballOrange,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onChangePhoto,
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: onChangePhoto,
          style: TextButton.styleFrom(
            foregroundColor: ShootIQTheme.basketballOrange,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          child: const Text('Change Photo'),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ShootIQTheme.cardBorder),
        boxShadow: ShootIQTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: ShootIQTheme.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ShootIQTheme.basketballOrange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: ShootIQTheme.basketballOrange, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: ShootIQTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: ShootIQTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: ShootIQTheme.cardBorder,
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: ShootIQTheme.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _OptionChips extends StatelessWidget {
  const _OptionChips({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option),
            selected: selected == option,
            onSelected: onSelected == null
                ? null
                : (value) {
                    if (value) onSelected!(option);
                  },
            selectedColor: ShootIQTheme.basketballOrange,
            backgroundColor: ShootIQTheme.surfaceElevated,
            labelStyle: TextStyle(
              color: selected == option
                  ? Colors.white
                  : ShootIQTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            side: BorderSide(
              color: selected == option
                  ? ShootIQTheme.basketballOrange
                  : ShootIQTheme.cardBorder,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            showCheckmark: false,
          ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ShootIQTheme.errorRed.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ShootIQTheme.errorRed.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: ShootIQTheme.errorRed,
          fontSize: 14,
          height: 1.35,
        ),
      ),
    );
  }
}
