import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

/// Related settings share a single outline; each row owns its operation.
class AppSettingGroup extends StatelessWidget {
  const AppSettingGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => M3EList(
    itemCount: children.length,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    itemBuilder: (context, index) => Material(
      type: MaterialType.transparency,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: ListTileTheme.merge(
          shape: const RoundedRectangleBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          child: children[index],
        ),
      ),
    ),
  );
}
