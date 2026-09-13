import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/adaptive_form_dialog.dart';
import '../../../theme/design_tokens.dart';

Future<TimeOfDay?> showScheduleTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) => showDialog<TimeOfDay>(
  context: context,
  animationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: AppMotion.surfaceEnter,
          reverseDuration: AppMotion.surfaceExit,
          curve: AppMotion.standardCurve,
        ),
  builder: (_) => _ScheduleTimeForm(initialTime: initialTime, title: helpText),
);

class _ScheduleTimeForm extends StatefulWidget {
  const _ScheduleTimeForm({required this.initialTime, this.title});
  final TimeOfDay initialTime;
  final String? title;

  @override
  State<_ScheduleTimeForm> createState() => _ScheduleTimeFormState();
}

class _ScheduleTimeFormState extends State<_ScheduleTimeForm> {
  final _formKey = GlobalKey<FormState>();
  late final _hour = TextEditingController(
    text: widget.initialTime.hour.toString().padLeft(2, '0'),
  );
  late final _minute = TextEditingController(
    text: widget.initialTime.minute.toString().padLeft(2, '0'),
  );

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      TimeOfDay(hour: int.parse(_hour.text), minute: int.parse(_minute.text)),
    );
  }

  Widget _field(TextEditingController controller, String label, int max) =>
      TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
        textInputAction: max == 23
            ? TextInputAction.next
            : TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (text) {
          final value = int.tryParse(text ?? '');
          return value == null || value > max ? '请输入 0–$max' : null;
        },
        onFieldSubmitted: (_) {
          if (max == 23) {
            FocusScope.of(context).nextFocus();
          } else {
            _confirm();
          }
        },
      );

  @override
  Widget build(BuildContext context) => AdaptiveFormDialog(
    title: widget.title ?? '排期时间',
    maxWidth: 360,
    contentBuilder: (context, width, short) => Form(
      key: _formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _field(_hour, '小时', 23)),
          const SizedBox(width: 16),
          Expanded(child: _field(_minute, '分钟', 59)),
        ],
      ),
    ),
    actions: OverflowBar(
      alignment: MainAxisAlignment.end,
      spacing: 8,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('确定')),
      ],
    ),
  );
}
