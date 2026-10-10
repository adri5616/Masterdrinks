import 'dart:ui';
import 'package:flutter/material.dart';
import '../../config/theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Border? border;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor ?? AppTheme.surfaceGlass,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ?? Border.all(color: AppTheme.borderGlass, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
