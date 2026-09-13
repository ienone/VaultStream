import 'package:flutter/material.dart';

import 'predictive_back_dialog.dart';

/// Returns true only on explicit discard. Draft guards and focus stay with
/// the editor; cancellation waits until its focus scope is available again.
Future<bool> showDiscardChangesDialog(
  BuildContext context, {
  required String title,
  required String message,
  AnimationStyle? animationStyle,
}) async {
  Future<Object?>? closed;
  final discard = await showDialog<bool>(
    context: context,
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : animationStyle,
    builder: (context) {
      closed = ModalRoute.of(context)?.completed;
      return PredictiveBackDialog(
        child: AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
    },
  );
  if (discard != true) await closed;
  return discard == true;
}
