import '../../models/content.dart';
import '../../../../core/media/media_asset.dart';

/// The visible copy is shared by card painting and its grid measurement.
class CollectionCardText {
  CollectionCardText(ShareCard content) {
    final rawTitle = content.title?.trim() ?? '';
    hasTitle = rawTitle.isNotEmpty && !['-', '无标题', '未命名内容'].contains(rawTitle);
    final matched = content.semanticSourceText?.trim() ?? '';
    final excerpt = matched.isNotEmpty
        ? matched
        : content.excerpt?.trim() ?? '';
    if (hasTitle) {
      final question = content.platform == 'zhihu'
          ? rawTitle.replaceFirst(RegExp(r'^回答[：:]\s*'), '')
          : rawTitle;
      primary = question.isEmpty ? rawTitle : question;
      final titlePrefix = rawTitle
          .replaceFirst(RegExp(r'(…|\.{3})$'), '')
          .trim();
      supporting = titlePrefix != rawTitle && excerpt.startsWith(titlePrefix)
          ? ''
          : excerpt.startsWith(rawTitle)
          ? excerpt.substring(rawTitle.length).trim()
          : excerpt;
    } else {
      primary = excerpt.isNotEmpty ? excerpt : _mediaOrSourceLabel(content);
      supporting = '';
    }
  }

  late final bool hasTitle;
  late final String primary;
  late final String supporting;
  int get maxLines => hasTitle ? 2 : 4;

  static String _mediaOrSourceLabel(ShareCard content) {
    final types = content.mediaAssets
        .where((asset) => asset.role != MediaRole.avatar)
        .map((asset) => asset.mediaType)
        .toSet();
    if (types.contains(MediaType.video)) return '视频';
    if (types.contains(MediaType.audio)) return '音频';
    if (types.contains(MediaType.image)) return '图片';
    final uri = Uri.tryParse(content.cleanUrl ?? content.url);
    return uri?.hasAuthority == true ? uri!.host : '';
  }
}
