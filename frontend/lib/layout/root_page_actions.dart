import 'package:material_ui/material_ui.dart';

import '../features/collection/widgets/dialogs/add_content_dialog.dart';

/// 保存属于页头动作区；工具统一归入导航。
class RootPageActions extends StatelessWidget {
  const RootPageActions({super.key});

  @override
  Widget build(BuildContext context) => PageAddButton(
    tooltip: '保存内容',
    onPressed: () => AddContentDialog.showAndNotify(context),
  );
}

class PageAddButton extends StatelessWidget {
  const PageAddButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        minimumSize: const Size(44, 44),
        shape: const StadiumBorder(),
      ),
      icon: const Icon(Icons.add_rounded),
    ),
  );
}
