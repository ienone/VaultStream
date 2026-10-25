import 'package:material_ui/material_ui.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../models/header_line.dart';
import '../../../../core/widgets/animated_expansion.dart';
import '../../../../theme/design_tokens.dart';

/// Reading navigation stays outside the article's document flow.
class ReadingOutlineBar extends StatefulWidget {
  const ReadingOutlineBar({
    super.key,
    required this.headers,
    required this.activeHeader,
    required this.progress,
    required this.onSelect,
  });

  final List<HeaderLine> headers;
  final ValueNotifier<String?> activeHeader;
  final ValueNotifier<double> progress;
  final ValueChanged<String> onSelect;

  @override
  State<ReadingOutlineBar> createState() => _ReadingOutlineBarState();
}

class _ReadingOutlineBarState extends State<ReadingOutlineBar> {
  LocalHistoryEntry? _entry;
  bool _disposing = false;
  bool get _expanded => _entry != null;

  void _close() => _entry?.remove();

  void _toggle() {
    if (_expanded) {
      _close();
      return;
    }
    final entry = LocalHistoryEntry(
      onRemove: () {
        _entry = null;
        if (!_disposing && mounted) setState(() {});
      },
    );
    ModalRoute.of(context)!.addLocalHistoryEntry(entry);
    setState(() => _entry = entry);
  }

  @override
  void dispose() {
    _disposing = true;
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      children: [
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const SizedBox.expand(),
            ),
          ),
        Positioned(
          key: const ValueKey('reading-outline-surface'),
          left: 16,
          right: 16,
          bottom: 8,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  elevation: 3,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedExpansion(
                        expanded: _expanded,
                        alignment: Alignment.bottomCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                (constraints.maxHeight -
                                        MediaQuery.paddingOf(context).bottom -
                                        74)
                                    .clamp(0, constraints.maxHeight * .6),
                          ),
                          child: _OutlineList(
                            headers: widget.headers,
                            activeHeader: widget.activeHeader.value,
                            onSelect: (id) {
                              _close();
                              widget.onSelect(id);
                            },
                          ),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: Listenable.merge([
                          widget.activeHeader,
                          widget.progress,
                        ]),
                        builder: (context, _) {
                          final current = widget.headers
                              .where(
                                (h) => h.uniqueId == widget.activeHeader.value,
                              )
                              .firstOrNull;
                          return Semantics(
                            button: true,
                            onTap: _toggle,
                            label:
                                '${_expanded ? '收起' : '展开'}目录，${current?.text ?? '文章开头'}，已读 ${(widget.progress.value * 100).round()}%',
                            excludeSemantics: true,
                            child: InkWell(
                              onTap: _toggle,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(
                                        begin: 0,
                                        end: widget.progress.value,
                                      ),
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : AppMotion.fast,
                                      builder: (context, progress, _) =>
                                          FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: progress,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: .18),
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: .10),
                                                    Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                        .withValues(alpha: 0),
                                                  ],
                                                  stops: const [0, .85, 1],
                                                ),
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.format_list_bulleted_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            current?.text ?? '目录',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '${(widget.progress.value * 100).round()}%',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                        const SizedBox(width: 8),
                                        AnimatedRotation(
                                          turns: _expanded ? .5 : 0,
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : AppMotion.stateChange,
                                          child: const Icon(
                                            Icons.expand_less_rounded,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
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

class _OutlineList extends StatefulWidget {
  const _OutlineList({
    required this.headers,
    required this.activeHeader,
    required this.onSelect,
  });
  final List<HeaderLine> headers;
  final String? activeHeader;
  final ValueChanged<String> onSelect;

  @override
  State<_OutlineList> createState() => _OutlineListState();
}

class _OutlineListState extends State<_OutlineList> {
  final _scroll = AutoScrollController(suggestedRowHeight: 48);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = widget.headers.indexWhere(
        (h) => h.uniqueId == widget.activeHeader,
      );
      if (index > 0) {
        _scroll.scrollToIndex(
          index,
          preferPosition: AutoScrollPosition.middle,
          duration: const Duration(milliseconds: 1),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minimumLevel = widget.headers
        .map((h) => h.level)
        .reduce((a, b) => a < b ? a : b);
    return Material(
      type: MaterialType.transparency,
      clipBehavior: Clip.hardEdge,
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        controller: _scroll,
        itemCount: widget.headers.length,
        itemBuilder: (context, index) {
          final header = widget.headers[index];
          return AutoScrollTag(
            key: ValueKey(header.uniqueId),
            index: index,
            controller: _scroll,
            child: ListTile(
              contentPadding: EdgeInsets.only(
                left: 24 + (header.level - minimumLevel).clamp(0, 3) * 12,
                right: 24,
              ),
              selected: header.uniqueId == widget.activeHeader,
              title: Text(header.text),
              onTap: () => widget.onSelect(header.uniqueId),
            ),
          );
        },
      ),
    );
  }
}
