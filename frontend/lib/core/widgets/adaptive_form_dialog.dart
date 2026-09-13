import 'package:flutter/material.dart';
import '../../theme/design_tokens.dart';
import 'predictive_back_dialog.dart';

/// One form tree across keyboard and size changes; low-height actions scroll.
class AdaptiveFormDialog extends StatefulWidget {
  const AdaptiveFormDialog({
    super.key,
    required this.title,
    required this.contentBuilder,
    required this.actions,
    this.maxWidth = AppPane.formMaxWidth,
  });
  final String title;
  final Widget Function(BuildContext context, double contentWidth, bool short)
  contentBuilder;
  final Widget actions;
  final double maxWidth;
  @override
  State<AdaptiveFormDialog> createState() => _AdaptiveFormDialogState();
}

class _AdaptiveFormDialogState extends State<AdaptiveFormDialog> {
  Size? _lastViewportSize;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    return PredictiveBackDialog(
      child: Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: availableHeight < 320 ? 8 : 24,
        ),
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final short = constraints.maxHeight < 320;
            if (_lastViewportSize != constraints.biggest) {
              _lastViewportSize = constraints.biggest;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
                  return;
                }
                final focusContext =
                    FocusManager.instance.primaryFocus?.context;
                if (focusContext != null) {
                  BuildContext target = focusContext;
                  focusContext.visitAncestorElements((element) {
                    if (element.widget is TextField) {
                      target = element;
                      return false;
                    }
                    return true;
                  });
                  Scrollable.ensureVisible(target, alignment: 0.5);
                }
              });
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(24, 24, 24, short ? 24 : 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          namesRoute: true,
                          child: Text(
                            widget.title,
                            style: theme.textTheme.headlineSmall,
                          ),
                        ),
                        const SizedBox(height: 24),
                        widget.contentBuilder(
                          context,
                          constraints.maxWidth - 48,
                          short,
                        ),
                        if (short) ...[
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerRight,
                            child: widget.actions,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!short)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: widget.actions,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
