import 'package:flutter/material.dart';

// 定义一个名为CollectionPage的无状态(Stateless)Widget类
class CollectionPage extends StatelessWidget {
  const CollectionPage({
    super.key,
  }); // 常量构造函数，接受一个可选的key参数，传递给父类StatelessWidget的构造函数。

  // override关键字表示重写父类的build方法
  @override
  Widget build(BuildContext context) {
    // 返回一个居中的布局Center Widget
    return Center(
      // Center Widget的子Widget是一个垂直排列的Column Widget
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center, // 主轴对齐方式为居中对齐
        // 定义Column的子Widget列表
        children: [
          Icon(
            Icons.perm_media_outlined, // 使用一个媒体图标
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16), // 添加一个高度为16像素的空白间距
          Text(
            'Content Collection', // 显示标题文本
            style: Theme.of(context).textTheme.headlineMedium, // 使用主题中的中等标题样式
          ),
          const SizedBox(height: 8), // 添加一个高度为8像素的空白间距
          const Text('这里将显示收集的内容。'), // 显示描述文本
        ],
      ),
    );
  }
}
// 这个文件当前只包含CollectionPage的基本UI结构，相当于背景板/默认内容