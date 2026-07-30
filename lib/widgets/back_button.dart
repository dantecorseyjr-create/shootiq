import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Small circular back button for onboarding and app screens.
class CustomBackButton extends StatelessWidget {
  const CustomBackButton({super.key});

  static const _size = 40.0;
  static const _background = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _background,
      shape: const CircleBorder(
        side: BorderSide(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _handleBack(context),
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: _size,
          height: _size,
          child: Center(
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    }
  }
}
