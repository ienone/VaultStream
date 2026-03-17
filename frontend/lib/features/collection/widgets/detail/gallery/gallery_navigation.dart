import 'package:flutter/material.dart';

import '../../../../../theme/design_tokens.dart';
import 'full_screen_gallery.dart';

Future<void> pushFullScreenGallery({
  required BuildContext context,
  required List<String> images,
  required int initialIndex,
  required String apiBaseUrl,
  String? apiToken,
  required int contentId,
  Color? contentColor,
  String? customHeroTag,
  void Function(int)? onPageChanged,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: AppMotion.fast,
      reverseTransitionDuration: AppMotion.fast,
      pageBuilder: (context, animation, secondaryAnimation) => FullScreenGallery(
        images: images,
        initialIndex: initialIndex,
        apiBaseUrl: apiBaseUrl,
        apiToken: apiToken,
        contentId: contentId,
        contentColor: contentColor,
        customHeroTag: customHeroTag,
        onPageChanged: onPageChanged,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppMotion.standardCurve,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    ),
  );
}
