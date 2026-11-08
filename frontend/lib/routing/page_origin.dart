import 'package:material_ui/material_ui.dart';

/// The actual row/card that opened a page, measured again on return.
class PageOrigin {
  PageOrigin(this.context);

  final BuildContext context;

  Rect? rectIn(BuildContext destination) {
    if (!context.mounted) return null;
    final source = context.findRenderObject();
    final target = Navigator.of(destination).overlay!.context
        .findRenderObject();
    if (source is! RenderBox || target is! RenderBox || !source.hasSize) {
      return null;
    }
    final rect =
        target.globalToLocal(source.localToGlobal(Offset.zero)) & source.size;
    return rect.overlaps(Offset.zero & target.size) ? rect : null;
  }
}

class OriginMaterialPage<T> extends MaterialPage<T> {
  const OriginMaterialPage({
    required super.child,
    super.key,
    super.canPop,
    this.origin,
  });

  final PageOrigin? origin;
}
