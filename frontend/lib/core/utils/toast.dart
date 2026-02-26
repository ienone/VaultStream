import 'package:flutter/material.dart';

class Toast {
  /// Shows a unified, stylized toast notification.
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    bool isError = false,
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

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        elevation: 2,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
