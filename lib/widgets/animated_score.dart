import 'package:flutter/material.dart';
import 'package:shootiq/config/theme.dart';

/// Counts from 0 (or [from]) up to [value] with a smooth ease-out.
class AnimatedScore extends StatelessWidget {
  const AnimatedScore({
    super.key,
    required this.value,
    this.from = 0,
    this.duration = const Duration(milliseconds: 900),
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.signed = false,
  });

  final int value;
  final int from;
  final Duration duration;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: from.toDouble(), end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        final n = animated.round();
        final text = signed && n > 0 ? '+$n' : '$n';
        return Text(
          '$prefix$text$suffix',
          style: style ??
              const TextStyle(
                color: ShootIQTheme.basketballOrange,
                fontSize: 36,
                fontWeight: FontWeight.w900,
              ),
        );
      },
    );
  }
}
