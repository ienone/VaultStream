import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';
import 'setting_components.dart';

class SettingsSlider extends StatefulWidget {
  const SettingsSlider({
    super.key,
    required this.value,
    required this.onSaved,
    required this.title,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatValue,
    required this.errorMessage,
  });
  final String title;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatValue;
  final String errorMessage;
  final double value;
  final Future<void> Function(double) onSaved;
  @override
  State<SettingsSlider> createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<SettingsSlider> {
  late double _value = widget.value;
  bool _dragging = false;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant SettingsSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_dragging && !_saving) {
      _value = widget.value;
    }
  }

  Future<void> _save(double value) async {
    setState(() {
      _dragging = false;
      _saving = true;
    });
    var saved = false;
    try {
      await widget.onSaved(value);
      saved = true;
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          formatApiErrorMessage(error, fallbackMessage: widget.errorMessage),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          if (!saved) _value = widget.value;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            widget.formatValue(_value),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
      Semantics(
        label: widget.title,
        child: Slider(
          value: _value,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: widget.formatValue(_value),
          onChangeStart: _saving ? null : (_) => _dragging = true,
          onChanged: _saving ? null : (value) => setState(() => _value = value),
          onChangeEnd: _saving ? null : _save,
        ),
      ),
    ],
  );
}
