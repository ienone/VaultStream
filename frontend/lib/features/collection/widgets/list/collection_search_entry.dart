import 'package:material_ui/material_ui.dart';

/// 在当前收藏列表中搜索，清除查询时保留其他筛选。
class CollectionSearchEntry extends StatelessWidget {
  const CollectionSearchEntry({
    super.key,
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => SearchBar(
          controller: controller,
          constraints: const BoxConstraints(minHeight: 48, maxWidth: 640),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          hintText: '搜索收藏库',
          leading: IconButton(
            tooltip: '搜索收藏库',
            onPressed: () => onSubmit(controller.text),
            icon: const Icon(Icons.search_rounded),
          ),
          onSubmitted: onSubmit,
          trailing: [
            if (value.text.isNotEmpty)
              IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  controller.clear();
                  onSubmit('');
                },
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      );
}
