import 'package:material_ui/material_ui.dart';

import 'dart:math' as math;

class Toast {
  /// Shows a unified, stylized toast notification.
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    bool isError = false,
    SnackBarAction? action,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final backgroundColor = isError
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;

    final textColor = isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;

    final iconColor = isError ? colorScheme.error : colorScheme.secondary;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon ??
                  (isError
                      ? Icons.error_outline_rounded
                      : Icons.info_outline_rounded),
              color: iconColor,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        width: math.min(480, MediaQuery.sizeOf(context).width - 32),
        elevation: 2,
        duration: Duration(seconds: action == null ? 3 : 5),
        persist: false,
        showCloseIcon: true,
        closeIconColor: textColor,
        action: action == null
            ? null
            : SnackBarAction(
                label: action.label,
                textColor: textColor,
                onPressed: action.onPressed,
              ),
      ),
    );
  }
}
