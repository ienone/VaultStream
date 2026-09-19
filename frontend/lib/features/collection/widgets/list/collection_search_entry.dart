import 'package:flutter/material.dart';

/// 当前列表直接输入；扩大到跨类型搜索时携带完整筛选上下文。
class CollectionSearchEntry extends StatelessWidget {
  const CollectionSearchEntry({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.onOpenPage,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onOpenPage;

  @override
  Widget build(BuildContext context) => SearchBar(
    controller: controller,
    constraints: const BoxConstraints(minHeight: 48),
    hintText: '搜索当前列表',
    leading: const Icon(Icons.search_rounded),
    onSubmitted: onSubmit,
    trailing: [
      IconButton(
        tooltip: '跨类型搜索',
        onPressed: onOpenPage,
        icon: const Icon(Icons.open_in_new_rounded),
      ),
    ],
  );
}
