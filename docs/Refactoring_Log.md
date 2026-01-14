  1. 前端样式分析 (Material 3 Expressive)
  当前项目遵循 Material 3 Expressive 设计语言，但在实现上存在大量硬编码。

   * 核心主题 (`AppTheme`): 已经定义了全局的 ColorScheme 和基础组件主题（Card, AppBar 等）。
   * 局部样式 (Hardcoded): 详情页中大量使用了手动计算的颜色和尺寸，而非复用 Theme。
       * 圆角: 普遍使用 BorderRadius.circular(24) 到 32 的大圆角，符合 Expressive 风格，但分散在各个 Container 中。
       * 阴影: 大量手写的 BoxShadow，例如 color: colorScheme.shadow.withValues(alpha: 0.1), blurRadius: 40，缺乏统一的 Elevation 定义。
       * 动态取色: 详情页实现了根据内容封面色 (coverColor) 动态生成 ColorScheme 的逻辑 (_getCustomTheme)，这部分实现得很好，但耦合在页面逻辑中。
       * 布局: 采用了响应式布局，区分 Mobile (Portrait) 和 Desktop (Landscape)，并在 Landscape 下针对不同平台（Twitter, Zhihu, Bilibili）有完全不同的布局策略。

  2. 代码质量问题：过长文件与冗余实现

  A. 过长代码文件
   * `content_detail_page.dart` (3543行): 这是最严重的问题点。
       * 全能上帝类: 包含了所有平台的布局逻辑 (Twitter/Weibo, Zhihu Answer, Markdown, Bilibili)、图片查看器 (_FullScreenGallery)、Markdown
         渲染器配置、数据解析逻辑。
       * 混合关注点: 业务逻辑（如重新解析、删除）、UI 布局、数据清洗（URL 映射）全部混杂。

  B. 冗余与重复实现
   * `content_detail_sheet.dart` vs `content_detail_page.dart`:
       * ContentDetailSheet (底部弹窗预览) 几乎完整复制了详情页的 数据清洗逻辑。
       * 重复代码:
           * _mapUrl: URL 代理与本地路径映射逻辑完全重复。
           * _getStoredMap & _extractAllMedia: 从元数据提取归档媒体的逻辑完全重复。
           * _getPlatformIcon: 平台图标判断逻辑重复。
           * _buildRichContent: Markdown 渲染逻辑高度相似但独立维护。
   * 分散的 UI 组件:
       * AuthorHeader (作者头像栏)、UnifiedStats (点赞/评论数据栏) 在 Page 和 Sheet 中都有相似实现，但未抽离为通用组件。

  3. 解耦重构方案

  为了解决上述问题，建议进行模块化拆分。目标是将 3500 行的大文件拆解为多个 < 300 行的小文件。

  Step 1: 提取核心工具类 (Utils)
  消除 Page 和 Sheet 之间的逻辑复制。
   * 创建 frontend/lib/features/collection/utils/content_parser.dart
       * ContentParser.mapUrl(String url, String baseUrl)
       * ContentParser.extractMedia(ContentDetail detail)
       * ContentParser.getStoredMap(ContentDetail detail)
       * ContentParser.getPlatformIcon(String platform)

  Step 2: 抽离通用 UI 组件 (Components)
  供 Page 和 Sheet 共同使用。
   * 创建 frontend/lib/features/collection/widgets/detail/components/
       * author_header.dart: 统一的作者信息栏。
       * unified_stats.dart: 统一的互动数据（点赞/评论/转发）展示组件。
       * tags_section.dart: 标签流式布局。
       * bvid_card.dart: B站 BV 号展示卡片。

  Step 3: 拆分详情页布局 (Layouts)
  根据 content_detail_page.dart 中的 _buildResponsiveLayout 逻辑，将不同模式拆分为独立 Widget。
   * 创建 frontend/lib/features/collection/widgets/detail/layout/
       * LIRT_landscape_layout.dart: 适用于 Twitter/微博 的左图右文布局。
       * zhihu_landscape_layout.dart: 适用于知乎回答的左文右侧栏布局。
       * markdown_landscape_layout.dart: 通用文章 + 目录布局。
       * video_landscape_layout.dart: B站视频布局。
       * portrait_detail_layout.dart: 统一的移动端/竖屏流式布局。

  Step 4: 独立复杂功能模块
   * 图片查看器: 将 _FullScreenGallery 独立为 frontend/lib/features/collection/widgets/detail/gallery/full_screen_gallery.dart。
   * Markdown 配置: 将 _HeaderBuilder, _CodeElementBuilder 移至 frontend/lib/features/collection/widgets/detail/markdown/markdown_config.dart。

  4. 推荐执行路径

   1. 优先执行 Step 1 (Utils): 立即创建一个工具类，将 content_detail_page.dart 中的 _mapUrl 等纯逻辑方法移动过去，并在 Page 和 Sheet
      中替换调用。这能马上减少代码重复。
   2. 执行 Step 2 (Components): 抽离 AuthorHeader 和 Stats，因为它们在视觉上最占篇幅且逻辑独立。
   3. 执行 Step 3 (Layouts): 将庞大的 _build...Layout 方法逐步迁移到独立文件。