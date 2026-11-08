import 'package:material_ui/material_ui.dart';

import 'app_select_menu.dart';

class AppMultiSelect extends StatelessWidget {
  const AppMultiSelect({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.hint = '不限',
  });
  final String label;
  final String hint;
  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => AppSelectMenu(
    label: label,
    summary: selected.isEmpty
        ? hint
        : selected.map((key) => options[key] ?? key).join('、'),
    enabled: options.isNotEmpty,
    items: (close) => [
      if (selected.isNotEmpty)
        MenuItemButton(
          closeOnActivate: false,
          onPressed: () => onChanged({}),
          child: const Text('清除选择'),
        ),
      for (final entry in options.entries)
        CheckboxMenuButton(
          closeOnActivate: false,
          value: selected.contains(entry.key),
          onChanged: (value) {
            final next = Set<String>.of(selected);
            value == true ? next.add(entry.key) : next.remove(entry.key);
            onChanged(next);
          },
          child: Text(entry.value),
        ),
    ],
  );
}
