import 'package:flutter/material.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../theme/design_tokens.dart';
import '../../../search/search_models.dart';
import 'collection_filter_form.dart';

Future<UnifiedSearchRequest?> editSearchFilters(
  BuildContext context,
  UnifiedSearchRequest request,
) {
  final child = CollectionFilterForm(request: request);
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  if (!WindowMetrics.of(context).widthClass.supportsSupportingPane) {
    return showModalBottomSheet<UnifiedSearchRequest>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: reducedMotion
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AppMotion.surfaceEnter,
              reverseDuration: AppMotion.surfaceExit,
            ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: ModalRoute.isCurrentOf(context) == true
              ? MediaQuery.viewInsetsOf(context).bottom
              : 0,
        ),
        child: FractionallySizedBox(
          heightFactor: .92,
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push(
    _FilterSideSheetRoute(
      reducedMotion: reducedMotion,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (context, animation, secondaryAnimation) => themes.wrap(
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 +
                  (ModalRoute.isCurrentOf(context) == true
                      ? MediaQuery.viewInsetsOf(context).bottom
                      : 0),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: SlideTransition(
                position: reducedMotion
                    ? const AlwaysStoppedAnimation(Offset.zero)
                    : animation.drive(
                        Tween(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).chain(CurveTween(curve: AppMotion.standardCurve)),
                      ),
                child: SizedBox(
                  width:
                      440 *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.25),
                  height: double.infinity,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppShape.sheetBorder,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: child,
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

class _FilterSideSheetRoute extends RawDialogRoute<UnifiedSearchRequest> {
  _FilterSideSheetRoute({
    required this.reducedMotion,
    required super.barrierLabel,
    required super.pageBuilder,
  }) : super(
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
         transitionDuration: reducedMotion
             ? Duration.zero
             : AppMotion.surfaceEnter,
         transitionBuilder: (context, animation, secondaryAnimation, child) =>
             child,
       );

  final bool reducedMotion;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : AppMotion.surfaceExit;
}
