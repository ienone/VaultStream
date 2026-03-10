import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DonutSegment {
  final double value;
  final Color color;
  final String label;

  const DonutSegment({
    required this.value,
    required this.color,
    required this.label,
  });
}

/// 甜甜圈图表 — 基于 CustomPainter，支持点击段落回调。
///
/// 点击检测通过角度计算实现，无需额外依赖。
class DonutChart extends StatefulWidget {
  final List<DonutSegment> segments;

  /// 显示在圆心的大数字（如总计）
  final String? centerLabel;

  /// 圆心大数字下方的小说明文字
  final String? centerSubLabel;

  final double diameter;
  final double strokeWidth;

  /// 点击某个弧段时回调该段的索引
  final void Function(int index)? onSegmentTap;

  const DonutChart({
    super.key,
    required this.segments,
    this.centerLabel,
    this.centerSubLabel,
    this.diameter = 160,
    this.strokeWidth = 26,
    this.onSegmentTap,
  });

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int? _pressedIndex;

  int? _getSegmentAt(Offset pos) {
    final c = Offset(widget.diameter / 2, widget.diameter / 2);
    final dx = pos.dx - c.dx;
    final dy = pos.dy - c.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    final outer = widget.diameter / 2;
    final inner = outer - widget.strokeWidth;

    // 点击位置必须在圆环范围内（±8px 容差）
    if (dist < inner - 8 || dist > outer + 8) return null;

    final total = widget.segments.fold(0.0, (s, e) => s + e.value);
    if (total == 0) return null;

    // -pi/2 偏移使起始角在顶部，顺时针旋转
    var angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    var cur = 0.0;
    for (int i = 0; i < widget.segments.length; i++) {
      final sw = (widget.segments[i].value / total) * 2 * math.pi;
      if (angle >= cur && angle < cur + sw) return i;
      cur += sw;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTapDown: (d) =>
          setState(() => _pressedIndex = _getSegmentAt(d.localPosition)),
      onTapUp: (d) {
        final idx = _getSegmentAt(d.localPosition);
        setState(() => _pressedIndex = null);
        if (idx != null) widget.onSegmentTap?.call(idx);
      },
      onTapCancel: () => setState(() => _pressedIndex = null),
      child: SizedBox(
        width: widget.diameter,
        height: widget.diameter,
        child: CustomPaint(
          painter: _DonutPainter(
            segments: widget.segments,
            strokeWidth: widget.strokeWidth,
            pressedIndex: _pressedIndex,
          ),
          child: widget.centerLabel == null
              ? null
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.centerLabel!,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.centerSubLabel != null)
                        Text(
                          widget.centerSubLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).scale(
          begin: const Offset(0.88, 0.88),
          end: const Offset(1, 1),
          curve: Curves.easeOutBack,
        );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final double strokeWidth;
  final int? pressedIndex;

  const _DonutPainter({
    required this.segments,
    required this.strokeWidth,
    this.pressedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final total = segments.fold(0.0, (s, e) => s + e.value);

    if (total == 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Colors.grey.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      return;
    }

    const startAngle = -math.pi / 2;
    var cur = startAngle;
    const gap = 0.025; // 段落间隙（弧度）

    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.value <= 0) continue;

      final sweep = (seg.value / total) * 2 * math.pi;
      final isPressed = i == pressedIndex;

      // 有足够空间时才加间隙
      final effectiveSweep = sweep > gap * 2 ? sweep - gap : sweep;
      final effectiveStart = sweep > gap * 2 ? cur + gap / 2 : cur;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        effectiveStart,
        effectiveSweep,
        false,
        Paint()
          ..color =
              isPressed ? seg.color : seg.color.withValues(alpha: 0.82)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isPressed ? strokeWidth * 1.18 : strokeWidth
          ..strokeCap = StrokeCap.butt,
      );

      cur += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.segments != segments || old.pressedIndex != pressedIndex;
}

/// 通用图例条目 — 带颜色圆点、标签、数量、百分比，可选点击
class DonutLegendItem extends StatelessWidget {
  final Color color;
  final Widget leading;
  final String label;
  final int value;
  final double percent;
  final int animationIndex;
  final VoidCallback? onTap;

  const DonutLegendItem({
    super.key,
    required this.color,
    required this.leading,
    required this.label,
    required this.value,
    required this.percent,
    required this.animationIndex,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              '$value',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 46,
              child: Text(
                '${percent.toStringAsFixed(1)}%',
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: colorScheme.outline),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: (animationIndex * 80).ms)
        .slideX(begin: 0.06, end: 0, curve: Curves.easeOut);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 通用饼图卡片抽象层
// ─────────────────────────────────────────────────────────────────────────────

/// 饼图卡片中的单个数据条目，封装显示信息与点击回调。
///
/// 调用方负责构造条目（含颜色、图标），[DonutOverviewCard] 只做渲染。
class DonutEntry {
  final String label;
  final int value;
  final Color color;

  /// 图例左侧图标区域（通常是同色 [Icon]）
  final Widget leading;

  /// 点击图例行或对应弧段时触发；为 null 则不可点击
  final VoidCallback? onTap;

  const DonutEntry({
    required this.label,
    required this.value,
    required this.color,
    required this.leading,
    this.onTap,
  });
}

/// 通用饼图概览卡片。
///
/// 接受 [DonutEntry] 列表，自动渲染圆环图 + 图例，响应式横纵布局。
/// 每个条目携带独立的 [VoidCallback]，调用方无需管理索引映射。
///
/// ```dart
/// DonutOverviewCard(
///   centerSubLabel: '总计',
///   totalOverride: realTotal,   // 真实总数（过滤条目时使用）
///   entries: [
///     DonutEntry(label: '待处理', value: 42, color: cs.primary,
///                leading: Icon(Icons.inbox, size: 16, color: cs.primary),
///                onTap: () => nav('/queue?status=pending')),
///   ],
/// )
/// ```
class DonutOverviewCard extends StatelessWidget {
  final List<DonutEntry> entries;

  /// 显示在圆心数字下方的副标签，如 "总计"
  final String? centerSubLabel;

  /// 数据全为 0 时的占位文字
  final String emptyMessage;

  /// 宽布局切换阈值（像素），默认 500
  final double wideBreakpoint;

  /// 覆盖圆心总数显示（当 entries 经过过滤、不代表真实总量时使用）
  final int? totalOverride;

  const DonutOverviewCard({
    super.key,
    required this.entries,
    this.centerSubLabel,
    this.emptyMessage = '暂无数据',
    this.wideBreakpoint = 500,
    this.totalOverride,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayTotal =
        totalOverride ?? entries.fold<int>(0, (s, e) => s + e.value);

    final segments = entries
        .map((e) => DonutSegment(
              value: e.value.toDouble(),
              color: e.color,
              label: e.label,
            ))
        .toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: displayTotal == 0
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(emptyMessage),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > wideBreakpoint;

                  final chart = DonutChart(
                    segments: segments,
                    diameter: 160,
                    strokeWidth: 26,
                    centerLabel: displayTotal.toString(),
                    centerSubLabel: centerSubLabel,
                    onSegmentTap: (i) => entries[i].onTap?.call(),
                  );

                  final legend = Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries.asMap().entries.map((e) {
                      final item = e.value;
                      final percent = displayTotal > 0
                          ? item.value / displayTotal * 100
                          : 0.0;
                      return DonutLegendItem(
                        color: item.color,
                        leading: item.leading,
                        label: item.label,
                        value: item.value,
                        percent: percent,
                        animationIndex: e.key,
                        onTap: item.onTap,
                      );
                    }).toList(),
                  );

                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        chart,
                        const SizedBox(width: 32),
                        Expanded(child: legend),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        Center(child: chart),
                        const SizedBox(height: 24),
                        legend,
                      ],
                    );
                  }
                },
              ),
      ),
    );
  }
}
