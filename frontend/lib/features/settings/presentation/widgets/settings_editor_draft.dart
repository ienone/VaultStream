import 'package:flutter/material.dart';

/// Keeps an editor's draft across theme changes and lazy-list recycling.
class SettingsEditorDraft extends StatefulWidget {
  const SettingsEditorDraft({
    super.key,
    required this.initialValues,
    required this.builder,
  });

  final Map<String, String> initialValues;
  final Widget Function(BuildContext, Map<String, TextEditingController>)
  builder;

  @override
  State<SettingsEditorDraft> createState() => _SettingsEditorDraftState();
}

class _SettingsEditorDraftState extends State<SettingsEditorDraft>
    with AutomaticKeepAliveClientMixin {
  late final Map<String, TextEditingController> _controllers = {
    for (final entry in widget.initialValues.entries)
      entry.key: TextEditingController(text: entry.value),
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant SettingsEditorDraft oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final entry in widget.initialValues.entries) {
      final controller = _controllers[entry.key]!;
      if (entry.value != oldWidget.initialValues[entry.key] &&
          controller.text == oldWidget.initialValues[entry.key]) {
        controller.text = entry.value;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(context, _controllers);
  }
}
