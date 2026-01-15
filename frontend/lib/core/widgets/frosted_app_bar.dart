import 'dart:ui';
import 'package:flutter/material.dart';

/// 毛玻璃效果的 AppBar
/// 统一处理背景模糊、透明度等样式
class FrostedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final double blurSigma;
  final double backgroundAlpha;
  final PreferredSizeWidget? bottom;

  const FrostedAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.blurSigma = 10,
    this.backgroundAlpha = 0.8,
    this.bottom,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      title: title,
      leading: leading,
      actions: actions,
      backgroundColor: theme.colorScheme.surface.withValues(alpha: backgroundAlpha),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: bottom,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
