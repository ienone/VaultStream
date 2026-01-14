import 'package:flutter/material.dart';
import '../../../models/content.dart';

class TagsSection extends StatelessWidget {
  final ContentDetail detail;

  const TagsSection({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    if (detail.tags.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: detail.tags
          .map(
            (tag) => Chip(
              label: Text(tag),
              labelStyle: Theme.of(context).textTheme.labelSmall,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHigh,
            ),
          )
          .toList(),
    );
  }
}
