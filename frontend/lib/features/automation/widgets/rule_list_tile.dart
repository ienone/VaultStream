import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../theme/design_tokens.dart';
import '../models/distribution_rule.dart';

class RuleListTile extends StatefulWidget {
  const RuleListTile({
    super.key,
    required this.rule,
    required this.backgroundColor,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onToggleEnabled,
  });

  final DistributionRule rule;
  final Color backgroundColor;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleEnabled;

  @override
  State<RuleListTile> createState() => _RuleListTileState();
}

class _RuleListTileState extends State<RuleListTile>
    with SingleTickerProviderStateMixin {
  static const _actionWidth = 80.0;
  late final _reveal = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );

  void _settle(bool open) {
    _reveal.animateTo(
      open ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.standard,
      curve: AppMotion.standardCurve,
    );
  }

  @override
  void didUpdateWidget(RuleListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected) _settle(false);
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final direction = Directionality.of(context) == TextDirection.ltr
        ? -1.0
        : 1.0;
    return TapRegion(
      onTapOutside: (_) => _settle(false),
      child: Semantics(
        customSemanticsActions: widget.onDelete == null
            ? null
            : {
                const CustomSemanticsAction(label: '显示删除按钮'): () =>
                    _settle(true),
              },
        child: GestureDetector(
          onHorizontalDragUpdate: widget.onDelete == null
              ? null
              : (details) {
                  _reveal.value += details.delta.dx * direction / _actionWidth;
                },
          onHorizontalDragEnd: widget.onDelete == null
              ? null
              : (details) {
                  final velocity = (details.primaryVelocity ?? 0) * direction;
                  _settle(
                    velocity.abs() > 300 ? velocity > 0 : _reveal.value > 0.5,
                  );
                },
          onHorizontalDragCancel: () => _settle(_reveal.value > 0.5),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AnimatedBuilder(
              animation: _reveal,
              builder: (context, child) => Stack(
                children: [
                  if (_reveal.value > 0)
                    PositionedDirectional(
                      end: 0,
                      top: 0,
                      bottom: 0,
                      width: _actionWidth,
                      child: Material(
                        color: colors.errorContainer,
                        child: InkWell(
                          onTap: () {
                            _settle(false);
                            widget.onDelete?.call();
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                color: colors.onErrorContainer,
                              ),
                              Text(
                                '删除',
                                style: TextStyle(
                                  color: colors.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Transform.translate(
                    offset: Offset(direction * _actionWidth * _reveal.value, 0),
                    child: child,
                  ),
                ],
              ),
              child: ColoredBox(
                color: widget.backgroundColor,
                child: DistributionNavigationTile(
                  title: widget.rule.name,
                  selected: widget.isSelected,
                  onTap: () {
                    if (_reveal.value > 0) {
                      _settle(false);
                    } else {
                      widget.onTap();
                    }
                  },
                  trailing: widget.onToggleEnabled == null
                      ? null
                      : Semantics(
                          label: '${widget.rule.name} 启用',
                          child: Switch(
                            value: widget.rule.enabled,
                            onChanged: widget.onToggleEnabled,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DistributionNavigationTile extends StatelessWidget {
  const DistributionNavigationTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.icon,
    this.trailing,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        selected: selected,
        selectedColor: colors.onSecondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: icon == null ? null : Icon(icon),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
