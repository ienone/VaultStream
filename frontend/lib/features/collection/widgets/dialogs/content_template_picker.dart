import 'package:material_ui/material_ui.dart';

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
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        constraints: const BoxConstraints(maxWidth: 480),
        child: ContentTemplatePicker(current: current),
      ),
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    clipBehavior: Clip.antiAlias,
    showDragHandle: false,
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
  static const _options = <(String, String)>[
    (autoValue, '自动判定'),
    ('article', '文章'),
    ('gallery', '图集 / 图文'),
    ('video', '视频'),
    ('audio', '音频'),
    ('link', '书签'),
  ];
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('阅读样式', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: current ?? autoValue,
                  onChanged: (value) => Navigator.pop(
                    context,
                    value == (current ?? autoValue) ? null : value,
                  ),
                  child: Column(
                    children: [
                      for (final (value, label) in _options)
                        RadioListTile<String>(
                          value: value,
                          title: Text(label),
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
