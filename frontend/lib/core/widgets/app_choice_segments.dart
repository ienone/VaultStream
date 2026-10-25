import 'package:material_ui/material_ui.dart';
import 'package:material_3_expressive/material_3_expressive.dart';

/// A bounded choice group; large labels keep their touch area by stacking.
class AppChoiceSegments<T> extends StatelessWidget {
  const AppChoiceSegments({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multiple = false,
    this.allowEmpty = false,
  });
  final Map<T, String> options;
  final Set<T> selected;
  final ValueChanged<Set<T>>? onChanged;
  final bool multiple;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final style = Theme.of(context).textTheme.labelLarge!;
      double width = 0;
      for (final label in options.values) {
        final measure = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        width += measure.width + (multiple ? 40 : 32);
        measure.dispose();
      }
      if (box.maxWidth >= width && (!allowEmpty || multiple)) {
        return SizedBox(
          width: double.infinity,
          child: M3ESegmentedButton<T>(
            segments: [
              for (final item in options.entries)
                M3ESegment(value: item.key, label: item.value),
            ],
            selected: selected,
            multiSelect: multiple,
            showSelectedIcon: multiple,
            enabled: onChanged != null,
            onSelectionChanged: onChanged ?? (_) {},
          ),
        );
      }
      return SizedBox(
        width: double.infinity,
        child: SegmentedButton<T>(
          direction: box.maxWidth < width ? Axis.vertical : Axis.horizontal,
          segments: [
            for (final item in options.entries)
              ButtonSegment(value: item.key, label: Text(item.value)),
          ],
          selected: selected,
          multiSelectionEnabled: multiple,
          emptySelectionAllowed: allowEmpty,
          showSelectedIcon: multiple,
          onSelectionChanged: onChanged,
        ),
      );
    },
  );
}
