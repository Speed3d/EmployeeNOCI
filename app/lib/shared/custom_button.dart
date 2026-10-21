import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Hint: زر مخصص بتصميم أنيق يدعم الوضعين والأنماط (Primary / Secondary / Outline)
class CustomButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isSecondary;
  final bool isDanger;
  final double? width;

  const CustomButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.isSecondary = false,
    this.isDanger = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.action(context);
    Color fg = AppColors.onAction(context);

    if (isSecondary) {
      bg = Colors.transparent;
      fg = Theme.of(context).brightness == Brightness.dark
          ? AppColors.goldBrightDark
          : AppColors.navy;
    } else if (isDanger) {
      bg = AppColors.danger;
      fg = Colors.white;
    }

    final buttonChild = isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          );

    return SizedBox(
      width: width,
      height: 44,
      child: isSecondary
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: fg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: buttonChild,
            )
          : ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: fg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: buttonChild,
            ),
    );
  }
}
