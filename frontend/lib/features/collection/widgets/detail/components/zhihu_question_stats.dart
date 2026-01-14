import 'package:flutter/material.dart';
import '../../../utils/format_utils.dart';
import 'unified_stat_item.dart';

class ZhihuQuestionStats extends StatelessWidget {
  final Map<String, dynamic> stats;

  const ZhihuQuestionStats({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          UnifiedStatItem(
            icon: Icons.person_add_alt,
            label: '关注',
            value: FormatUtils.formatCount(stats['follower_count']),
          ),
          UnifiedStatItem(
            icon: Icons.remove_red_eye_outlined,
            label: '浏览',
            value: FormatUtils.formatCount(stats['visit_count']),
          ),
          UnifiedStatItem(
            icon: Icons.question_answer_outlined,
            label: '回答',
            value: FormatUtils.formatCount(stats['answer_count']),
          ),
        ],
      ),
    );
  }
}
