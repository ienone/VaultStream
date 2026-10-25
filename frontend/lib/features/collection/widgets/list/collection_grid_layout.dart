import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';

import '../../models/content.dart';
import '../../../../core/media/media_asset.dart';
import 'collection_card_text.dart';

/// 端点尺寸只在数据、字号或窗口变化时计算，动画帧只插值几何位置。
class CollectionGridMetrics {
  CollectionGridMetrics(
    List<ShareCard> items,
    double overviewWidth,
    double listWidth,
    double scale,
    TextTheme textTheme,
    TextDirection direction,
  ) : columns = (overviewWidth / (300 * scale)).floor().clamp(1, 4) {
    final imageHeight =
        ((overviewWidth - 24 - 8 * (columns - 1)) / columns - 24) / 2.4;
    for (final item in items) {
      final hasImage = item.mediaAssets.any(
        (asset) =>
            asset.mediaType == MediaType.image &&
            asset.role != MediaRole.avatar &&
            asset.sources.isNotEmpty,
      );
      final status =
          item.isNsfw ||
          ['parse_failed', 'processing', 'unprocessed'].contains(item.status);
      final copy = CollectionCardText(item);
      final primaryStyle = copy.hasTitle
          ? textTheme.titleMedium!
          : textTheme.bodyMedium!;
      final textWidth =
          ((overviewWidth - 24 - 8 * (columns - 1)) / columns -
                  24 -
                  (overviewWidth < 600 && hasImage ? 100 : 0))
              .clamp(1.0, double.infinity);
      double measure(
        String value,
        TextStyle style,
        int lines, {
        double? width,
      }) {
        if (value.isEmpty) return 0;
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          maxLines: lines,
          textDirection: direction,
          textScaler: TextScaler.linear(scale),
        )..layout(maxWidth: width ?? textWidth);
        final height = painter.height.ceilToDouble();
        painter.dispose();
        return height;
      }

      final primaryHeight = measure(copy.primary, primaryStyle, copy.maxLines);
      final supportingHeight = copy.supporting.isEmpty
          ? 0
          : 8 + measure(copy.supporting, textTheme.bodySmall!, 2);
      final statusHeight = status ? 16 + 16 * scale : 0;
      final text = primaryHeight + supportingHeight + statusHeight;
      final listTextWidth =
          (listWidth -
                  48 -
                  (hasImage && (listWidth - 48) / scale >= 200 ? 100 : 0))
              .clamp(1.0, double.infinity);
      final listText =
          measure(
            copy.primary,
            primaryStyle,
            copy.maxLines,
            width: listTextWidth,
          ) +
          (copy.supporting.isEmpty
              ? 0
              : 8 +
                    measure(
                      copy.supporting,
                      textTheme.bodySmall!,
                      2,
                      width: listTextWidth,
                    )) +
          statusHeight;
      final base = 24 + 32 * scale + 12;
      listHeights.add(base + math.max(hasImage ? 64 : 0, listText) + 4);
      gridHeights.add(
        (overviewWidth < 600
                ? base + math.max(hasImage ? 64 : 0, text)
                : base +
                      text +
                      (hasImage ? imageHeight.clamp(80, 160) + 12 : 0)) +
            4,
      );
    }
    final columnOffsets = List<double>.filled(columns, 0);
    double listOffset = 0, maxGridEnd = 0;
    for (var i = 0; i < items.length; i++) {
      var column = 0;
      for (var candidate = 1; candidate < columns; candidate++) {
        if (columnOffsets[candidate] < columnOffsets[column]) {
          column = candidate;
        }
      }
      gridColumns.add(column);
      gridOffsets.add(columnOffsets[column]);
      final end = columnOffsets[column] + gridHeights[i];
      maxGridEnd = math.max(maxGridEnd, end);
      gridMaxEnds.add(maxGridEnd);
      columnOffsets[column] = end + 8;
      listOffsets.add(listOffset);
      listOffset += listHeights[i] + 4;
    }
  }
  final int columns;
  final gridHeights = <double>[], listHeights = <double>[];
  final gridOffsets = <double>[], listOffsets = <double>[];
  final gridMaxEnds = <double>[];
  final gridColumns = <int>[];
}

class CollectionGridDelegate extends SliverGridDelegate {
  const CollectionGridDelegate({
    required this.metrics,
    required this.progress,
    required this.scrollGeometry,
  });
  final CollectionGridMetrics metrics;
  final double progress;
  final CollectionGridScrollGeometry scrollGeometry;
  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final layout = _CollectionGridLayout(
      metrics,
      progress,
      constraints.crossAxisExtent,
      axisDirectionIsReversed(constraints.crossAxisDirection),
    );
    scrollGeometry._update(layout);
    return layout;
  }

  @override
  bool shouldRelayout(CollectionGridDelegate oldDelegate) =>
      metrics != oldDelegate.metrics || progress != oldDelegate.progress;
}

class _CollectionGridLayout extends SliverGridLayout {
  const _CollectionGridLayout(
    this.metrics,
    this.progress,
    this.width,
    this.reversed,
  );
  final CollectionGridMetrics metrics;
  final double progress, width;
  final bool reversed;
  int get columns => metrics.columns;
  double height(int index) =>
      metrics.gridHeights[index] * (1 - progress) +
      metrics.listHeights[index] * progress;
  double offset(int index) =>
      metrics.gridOffsets[index] * (1 - progress) +
      metrics.listOffsets[index] * progress;
  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final count = columns + (1 - columns) * progress;
    final childWidth = (width - 8 * (count - 1)) / count;
    final x = metrics.gridColumns[index] * (childWidth + 8) * (1 - progress);
    return SliverGridGeometry(
      scrollOffset: offset(index),
      crossAxisOffset: reversed ? width - childWidth - x : x,
      mainAxisExtent: height(index),
      crossAxisExtent: childWidth,
    );
  }

  int _firstEndingAfter(double value) {
    var low = 0, high = metrics.gridOffsets.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      final prefixEnd =
          metrics.gridMaxEnds[mid] * (1 - progress) +
          (metrics.listOffsets[mid] + metrics.listHeights[mid]) * progress;
      if (prefixEnd >= value) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }

  int _lastStartingBefore(double value) {
    var low = 0, high = metrics.gridOffsets.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (offset(mid) <= value) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) =>
      _firstEndingAfter(scrollOffset);
  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) =>
      _lastStartingBefore(scrollOffset);
  @override
  double computeMaxScrollOffset(int childCount) => childCount == 0
      ? 0
      : metrics.gridMaxEnds[childCount - 1] * (1 - progress) +
            (metrics.listOffsets[childCount - 1] +
                    metrics.listHeights[childCount - 1]) *
                progress;
}

/// 布局改变时以视口顶部的内容为锚点，而不是复用不同布局的绝对像素。
class CollectionGridScrollGeometry {
  _CollectionGridLayout? _current, _previous;
  int? _anchorIndex;
  double _anchorFraction = 0;
  void _update(_CollectionGridLayout next) {
    final old = _current;
    if (old != null &&
        (old.progress != next.progress || old.metrics != next.metrics)) {
      _previous ??= old;
    }
    _current = next;
  }

  double remap(double pixels) {
    final old = _previous;
    _previous = null;
    final next = _current;
    if (old == null ||
        next == null ||
        pixels <= 4 ||
        old.metrics.gridOffsets.isEmpty ||
        next.metrics.gridOffsets.isEmpty) {
      return pixels;
    }
    if (_anchorIndex == null) {
      var index = old._lastStartingBefore(pixels - 4);
      _anchorIndex = index;
      _anchorFraction = (pixels - 4 - old.offset(index)) / old.height(index);
    }
    final index = _anchorIndex!.clamp(0, next.metrics.gridOffsets.length - 1);
    final result =
        4 + next.offset(index) + _anchorFraction * next.height(index);
    if (next.progress == 0 || next.progress == 1) _anchorIndex = null;
    return result;
  }
}

class CollectionGridScrollPhysics extends ScrollPhysics {
  const CollectionGridScrollPhysics({required this.geometry, super.parent});
  final CollectionGridScrollGeometry geometry;
  @override
  CollectionGridScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      CollectionGridScrollPhysics(
        geometry: geometry,
        parent: buildParent(ancestor),
      );
  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) => geometry
      .remap(newPosition.pixels)
      .clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
}
