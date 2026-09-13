import 'package:flutter/material.dart';

import '../../../../theme/design_tokens.dart';

class OnboardingFeatureCard extends StatefulWidget {
  const OnboardingFeatureCard({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.configuration,
  });

  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget configuration;

  @override
  State<OnboardingFeatureCard> createState() => _OnboardingFeatureCardState();
}

class _OnboardingFeatureCardState extends State<OnboardingFeatureCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _height;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: AppMotion.contentSwap,
          value: widget.value ? 1 : 0,
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) setState(() {});
        });
    _height = _controller.drive(CurveTween(curve: AppMotion.standardCurve));
  }

  @override
  void didUpdateWidget(covariant OnboardingFeatureCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.value ? 1 : 0;
      } else if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = widget.value ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: Icon(widget.icon),
          title: Text(widget.title),
          value: widget.value,
          onChanged: widget.onChanged,
        ),
        Offstage(
          offstage: !widget.value && _controller.isDismissed,
          child: ExcludeFocus(
            excluding: !widget.value,
            child: ExcludeSemantics(
              excluding: !widget.value,
              child: IgnorePointer(
                ignoring: !widget.value,
                child: SizeTransition(
                  sizeFactor: _height,
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: widget.configuration,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
