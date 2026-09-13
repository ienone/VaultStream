import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

/// A named, keyboard-operable media entry that preserves child retry actions.
class MediaImageButton extends StatefulWidget {
  const MediaImageButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.child,
    this.selected,
    this.borderRadius = AppShape.cardBorder,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final bool? selected;
  final BorderRadius borderRadius;

  @override
  State<MediaImageButton> createState() => _MediaImageButtonState();
}

class _MediaImageButtonState extends State<MediaImageButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: widget.label,
    button: widget.onPressed != null,
    selected: widget.selected,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onPressed,
        onFocusChange: (focused) => setState(() => _focused = focused),
        borderRadius: widget.borderRadius,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: _focused
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: widget.child,
        ),
      ),
    ),
  );
}
