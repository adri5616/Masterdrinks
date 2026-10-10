import 'package:flutter/material.dart';
import '../../config/theme.dart';

class NumberPad extends StatelessWidget {
  final Function(String digit) onDigitTap;
  final VoidCallback onClear;
  final VoidCallback onDelete;
  final VoidCallback? onSubmit;

  const NumberPad({
    super.key,
    required this.onDigitTap,
    required this.onClear,
    required this.onDelete,
    this.onSubmit,
  });

  Widget _buildKey(String label, {VoidCallback? onTap, IconData? icon, Color? color}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: AppTheme.amberGold.withOpacity(0.3),
            child: Ink(
              height: 64,
              decoration: BoxDecoration(
                color: color ?? AppTheme.surfaceGlass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.borderGlass, width: 1),
              ),
              child: Center(
                child: icon != null
                    ? Icon(icon, color: Colors.white70, size: 26)
                    : Text(
                        label,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _buildKey('1', onTap: () => onDigitTap('1')),
            _buildKey('2', onTap: () => onDigitTap('2')),
            _buildKey('3', onTap: () => onDigitTap('3')),
          ],
        ),
        Row(
          children: [
            _buildKey('4', onTap: () => onDigitTap('4')),
            _buildKey('5', onTap: () => onDigitTap('5')),
            _buildKey('6', onTap: () => onDigitTap('6')),
          ],
        ),
        Row(
          children: [
            _buildKey('7', onTap: () => onDigitTap('7')),
            _buildKey('8', onTap: () => onDigitTap('8')),
            _buildKey('9', onTap: () => onDigitTap('9')),
          ],
        ),
        Row(
          children: [
            _buildKey('C', onTap: onClear, color: Colors.redAccent.withOpacity(0.15)),
            _buildKey('0', onTap: () => onDigitTap('0')),
            _buildKey('', icon: Icons.backspace_outlined, onTap: onDelete, color: Colors.orangeAccent.withOpacity(0.15)),
          ],
        ),
      ],
    );
  }
}
