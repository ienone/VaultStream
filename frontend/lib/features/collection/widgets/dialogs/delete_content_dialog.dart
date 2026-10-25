import 'package:material_ui/material_ui.dart';

Future<bool?> confirmContentDeletion(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认删除'),
      content: const Text('将删除这条内容及其已归档的本地媒体。此操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          child: const Text('删除'),
        ),
      ],
    ),
  );
}
