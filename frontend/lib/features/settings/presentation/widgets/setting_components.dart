import 'package:material_ui/material_ui.dart';

import '../../../../core/widgets/app_setting_group.dart';

import '../../../../core/utils/toast.dart';
import '../../../../core/network/api_client.dart';
import '../../../../theme/design_tokens.dart';

// SectionHeader 已迁移至 core/widgets，此处重新导出保持向后兼容。
export '../../../../core/widgets/section_header.dart' show SectionHeader;

class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppSettingGroup(children: children);
}

class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.onTap,
    this.showArrow = true,
    this.stackTrailing = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showArrow;
  final bool stackTrailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            stackTrailing && constraints.maxWidth < AppPane.formMaxWidth;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 4,
          ),
          leading: icon == null ? null : Icon(icon, color: iconColor),
          title: Text(title),
          subtitle: stacked && trailing != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (subtitle?.isNotEmpty ?? false) Text(subtitle!),
                    const SizedBox(height: 12),
                    trailing!,
                  ],
                )
              : (subtitle?.isNotEmpty ?? false)
              ? Text(subtitle!)
              : null,
          trailing: stacked
              ? null
              : trailing ??
                    (showArrow && onTap != null
                        ? const Icon(Icons.chevron_right_rounded)
                        : null),
          onTap: onTap,
        );
      },
    );
  }
}

class ExpandableSettingTile extends StatefulWidget {
  const ExpandableSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.expandedContent,
    this.dense = false,
  });

  final String title;
  final Widget? subtitle;
  final IconData? icon;
  final Widget expandedContent;
  final bool dense;

  @override
  State<ExpandableSettingTile> createState() => _ExpandableSettingTileState();
}

class _ExpandableSettingTileState extends State<ExpandableSettingTile>
    with AutomaticKeepAliveClientMixin {
  bool _expanded = false;
  bool _hasExpanded = false;

  @override
  bool get wantKeepAlive => _expanded;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final shape =
        ListTileTheme.of(context).shape ??
        const RoundedRectangleBorder(borderRadius: AppShape.cardMediaBorder);
    return ListTileTheme.merge(
      shape: shape,
      child: ExpansionTile(
        title: Text(widget.title, style: theme.textTheme.titleMedium),
        subtitle: widget.subtitle == null
            ? null
            : DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                child: widget.subtitle!,
              ),
        leading: widget.icon == null ? null : Icon(widget.icon, size: 22),
        tilePadding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: widget.dense ? 0 : 4,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        shape: shape,
        collapsedShape: shape,
        clipBehavior: Clip.antiAlias,
        maintainState: _hasExpanded,
        expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: AppMotion.contentSwap,
                curve: AppMotion.standardCurve,
              ),
        onExpansionChanged: (expanded) {
          setState(() {
            _expanded = expanded;
            _hasExpanded |= expanded;
          });
          updateKeepAlive();
        },
        children: [
          ExcludeFocus(
            excluding: !_expanded,
            child: SizedBox(
              width: double.infinity,
              child: widget.expandedContent,
            ),
          ),
        ],
      ),
    );
  }
}

void showToast(BuildContext context, String message) {
  Toast.show(context, message);
}

class LoadingGroup extends StatelessWidget {
  const LoadingGroup({super.key});
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 72,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class SettingLoadFailure extends StatelessWidget {
  const SettingLoadFailure({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        const Text('设置读取失败'),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重试'),
        ),
      ],
    ),
  );
}

class SettingSaveButton extends StatefulWidget {
  const SettingSaveButton({
    super.key,
    required this.onPressed,
    required this.child,
  });
  final Future<void> Function() onPressed;
  final Widget child;

  @override
  State<SettingSaveButton> createState() => _SettingSaveButtonState();
}

class _SettingSaveButtonState extends State<SettingSaveButton> {
  bool _saving = false;
  bool _failed = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onPressed();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      FilledButton.tonal(
        onPressed: _saving ? null : _save,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(opacity: _saving ? 0 : 1, child: widget.child),
            if (_saving)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
      if (_failed)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '保存失败，请重试',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

/// An immediate setting write keeps its progress and error next to the control.
class SettingSwitch extends StatefulWidget {
  const SettingSwitch({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
    this.shape,
  });
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;
  final EdgeInsetsGeometry contentPadding;
  final ShapeBorder? shape;
  @override
  State<SettingSwitch> createState() => _SettingSwitchState();
}

class _SettingSwitchState extends State<SettingSwitch> {
  bool _saving = false;
  String? _error;
  bool? _requested;
  Future<void> _save(bool value) async {
    setState(() {
      _saving = true;
      _error = null;
      _requested = value;
    });
    try {
      await widget.onChanged(value);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = formatApiErrorMessage(error, fallbackMessage: '保存失败'),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        title: widget.title,
        subtitle: widget.subtitle,
        value: _saving ? _requested! : widget.value,
        contentPadding: widget.contentPadding,
        shape: widget.shape,
        onChanged: _saving ? null : _save,
      ),
      if (_saving) const LinearProgressIndicator(),
      if (_error != null)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: () => _save(_requested!),
              child: const Text('重试'),
            ),
          ],
        ),
    ],
  );
}
