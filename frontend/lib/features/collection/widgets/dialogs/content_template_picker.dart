import 'package:flutter/material.dart';
import '../../../../core/widgets/predictive_back_dialog.dart';
import '../../../../theme/design_tokens.dart';

Future<String?> showContentTemplatePicker(
  BuildContext context,
  String? current,
) {
  final animation = MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: AppMotion.surfaceEnter,
          reverseDuration: AppMotion.surfaceExit,
          curve: AppMotion.standardCurve,
        );
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 600 && size.height >= 480) {
    return showDialog<String>(
      context: context,
      animationStyle: animation,
      builder: (_) => PredictiveBackDialog(
        child: Dialog(
          clipBehavior: Clip.antiAlias,
          constraints: const BoxConstraints(maxWidth: 480),
          child: ContentTemplatePicker(current: current),
        ),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    showDragHandle: true,
    sheetAnimationStyle: animation,
    builder: (_) =>
        SafeArea(top: false, child: ContentTemplatePicker(current: current)),
  );
}

class ContentTemplatePicker extends StatelessWidget {
  const ContentTemplatePicker({super.key, required this.current});
  final String? current;
  static const autoValue = '__auto__';
  // Values match the backend LayoutType enum; auto clears the override.
  static const _options = <(String, String, String)>[
    (autoValue, '自动判定', '由来源和内容特征决定'),
    ('article', '文章', '连续阅读，正文限宽'),
    ('gallery', '图集 / 图文', '媒体为主体'),
    ('video', '视频', '播放器与简介'),
    ('audio', '音频', '封面、播放与文字说明'),
    ('link', '书签', '链接与保存记录'),
  ];
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '切换模板',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '关闭模板选择',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    '手动选择后，重新解析会保留此模板。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                RadioGroup<String>(
                  groupValue: current ?? autoValue,
                  onChanged: (value) => Navigator.pop(
                    context,
                    value == (current ?? autoValue) ? null : value,
                  ),
                  child: Column(
                    children: [
                      for (final (value, label, hint) in _options)
                        RadioListTile<String>(
                          value: value,
                          title: Text(label),
                          subtitle: Text(hint),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppShape.cardBorder,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
