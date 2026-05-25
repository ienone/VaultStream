import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class PlatformBadge extends StatelessWidget {
  final String platform;

  const PlatformBadge({super.key, required this.platform});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color color;
    Widget icon;
    String label = platform.toUpperCase();

    switch (platform.toLowerCase()) {
      case 'twitter':
      case 'x':
        color = isDark ? Colors.white : Colors.black;
        icon = FaIcon(FontAwesomeIcons.xTwitter, size: 10);
        label = 'X';
        break;
      case 'bilibili':
        color = const Color(0xFFFB7299);
        icon = FaIcon(FontAwesomeIcons.bilibili, size: 10);
        break;
      case 'xiaohongshu':
        color = const Color(0xFFFF2442);
        icon = const Icon(Icons.book, size: 10);
        label = '小红书';
        break;
      case 'weibo':
        color = const Color(0xFFE6162D);
        icon = FaIcon(FontAwesomeIcons.weibo, size: 10);
        label = '微博';
        break;
      case 'zhihu':
        color = const Color(0xFF0084FF);
        icon = FaIcon(FontAwesomeIcons.zhihu, size: 10);
        label = '知乎';
        break;
      case 'ku_an':
        color = const Color(0xFF1E88E5);
        icon = const Icon(Icons.android, size: 10);
        label = '酷安';
        break;
      default:
        color = theme.colorScheme.secondary;
        icon = const Icon(Icons.link, size: 10);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 50 : 30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTheme(
            data: IconThemeData(color: color, size: 10),
            child: icon,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
