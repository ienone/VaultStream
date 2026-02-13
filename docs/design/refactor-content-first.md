# VaultStream 前后端改造方案：从平台驱动到内容驱动

## 背景与目标

随着 `UniversalAdapter`（通用智能解析）的引入，VaultStream 的内容来源覆盖任意网页。

当前的架构是 **"平台驱动 (Platform-First)"** 的：
*   后端根据 URL 域名硬编码判断 `platform`。
*   前端根据 `platform` 字段 `if-else` 选择渲染组件（B站渲染器、微博渲染器）。

这种模式导致通用解析器抓取回来的内容（可能是文章、也可能是视频）无法在前端正确展示。

**目标**：重构为 **"内容驱动 (Content-First)"** 架构，引入 `layout_type` 概念，实现后端智能分类，前端通用渲染。

---

## 1. 数据库与后端改造 (Backend)

### 1.1 数据模型扩展 (`models.py`)

在 `Content` 表中新增 `layout_type` 字段，用于指示该内容的最佳展示形态。

```python
class LayoutType(str, Enum):
    ARTICLE = "article"      # 长文 (知乎专栏, 博客, 新闻) - 侧重 Markdown 渲染
    VIDEO = "video"          # 纯视频 (B站, YouTube) - 侧重播放器
    GALLERY = "gallery"      # 画廊 (微博, 小红书， Twitter/X) - 侧重图片轮播
    AUDIO = "audio"          # 音频 (Podcast)
    LINK = "link"            # 纯链接 (无法解析时)

class Content(Base):
    # ...
    layout_type = Column(SQLEnum(LayoutType), default=LayoutType.ARTICLE, index=True)
    # ...
```

### 1.2 适配器层改造 (`UniversalAdapter` & `AdapterFactory`)

所有适配器在返回 `ParsedContent` 时，必须指定 `layout_type`。

*   **UniversalAdapter 智能判断**:
    *   LLM 在提取时，增加一个字段 `detected_type`。
    *   逻辑判断：
        *   大模型根据平台&内容特征判断类型，提供参考逻辑如下
            *   如果内容主体是 `video_url` -> `VIDEO`
            *   如果正文为图文混杂的格式，解析为`article`
            *   如果图片全部都是在文首或者文末位置，解析为 `GALLERY`
            *   如果内容主体是`audio_url` -> `AUDIO`
            *   否则默认为 `ARTICLE`
*   现有专门解析器的 `layout_type` 设置按照其前端对应的样式来设置，例如：
    *   **BilibiliAdapter**: 视频当前没有存档video只有封面图文件，解析为`GALLERY` ,动态内容解析为`GALLERY`,opus或文章内容解析为`ARTICLE`
    *   **WeiboAdapter**: 默认为 `GALLERY`
    *   其余各部分解析器结合前端展示逻辑进行设置
    *   修改完成之后生成一份设置文档方便查阅&修改
  
### 1.3 动态配置迁移 (`SystemSettings`)

将非敏感配置从 `.env` 迁移到数据库，并提供 API。

*   **新增 API**:
    *   `GET /api/settings/discovery`: 获取发现规则、黑白名单。
    *   `POST /api/settings/discovery`: 修改配置。

---

## 2. 前端改造 (Frontend)

### 2.1 详情页路由重构

详情页路由采用基于布局类型的分发：

```dart
switch (content.layoutType) {
  case 'video': return VideoLayout(content);
  case 'gallery': return GalleryLayout(content);
  default: return ArticleLayout(content);
}
```

### 2.2 通用组件库 (已有实现)

现有组件已满足需求，组件映射如下：

| 设计名称 | 实际组件 | 文件位置 |
|----------|----------|----------|
| UnifiedHeader | `AuthorHeader` | `components/author_header.dart` |
| UnifiedFooter | `UnifiedStats` | `components/unified_stats.dart` |
| MarkdownViewer | `RichContent` | `components/rich_content.dart` |
| MediaGrid | `MediaGrid` | `components/media_grid.dart` *(新增)* |

1.  **`AuthorHeader`**: 作者头像（渐变边框）、作者名、发布时间、平台图标、点击跳转
2.  **`UnifiedStats`**: 互动数据栏（阅读/点赞/评论），自动隐藏为 0 的数据项
3.  **`RichContent`**: Markdown 渲染（代码块、引用、LaTeX）、图片 Hero 动画、目录支持
4.  **`MediaGrid`** *(新增)*: 自适应布局（竖屏九宫格、横屏缩略图滚动）
5.  **`ContentSideInfoCard`**: 整合以上组件 + 平台特有逻辑（知乎关联问题等）

- 各个格式中的图片媒体资源点击放大后的全屏预览界面最好复用同一套当前的图片查看器逻辑，重点是保留无缝放大&缩小的交互体验，或者你可以查找到现有的库来实现这一点？如果是那样，请仔细对比对齐功能，只需要修改样式即可。
- 样式布局适配时要遵循Material 3 Expressive Design规范，设计时可以参考 https://m3.material.io/ 的官方文档规范。保持整体风格一致。要考虑到横屏竖屏变更时的自适应布局。
- 样式需要配置合适且有逻辑符合直觉动画效果，最好能够额外引入预测性返回手势动画，提升用户体验。
- 所有的重构都要flutter analyzer检查通过，确保没有任何警告和错误。

### 2.3 设置页新增

在设置页面增加 "Discovery & AI" 板块：
*   [开关] 启用 AI 自动发现
*   [列表] 订阅主题管理 (Tag input)
*   [滑块] 质量阈值 (只保存 AI 评分 > N 的内容)
*   ……

### 2.4 用户手动配置优化

* 接受通过系统分享获得的链接时，编辑选项界面支持手动选择前端显示样式，这个优先级高于后端自动识别的结果
* 在收藏库中新增内容弹出的二级界面，同步上一条修改
* 在内容详情页的编辑界面，新增修改布局类型的选项，方便用户纠正错误识别

---

## 3. 实施路线图

### Phase 1: 后端数据层 ✅
- [x] 引入 `UniversalAdapter`。
- [x] 数据库新增 `layout_type` 字段 (models.py 已更新，需要 Migration)。
- [x] 新增 `layout_type_override` 字段支持用户覆盖。
- [x] 新增 `effective_layout_type` 计算属性。
- [x] 更新所有 Adapter 填充 `layout_type`：
  - [x] BilibiliAdapter (video/article/dynamic/bangumi/live)
  - [x] WeiboAdapter (status/user_profile)
  - [x] TwitterFxAdapter (tweet)
  - [x] ZhihuAdapter (answer/article/question/pin/user_profile/column/collection)
  - [x] XiaohongshuAdapter (note/user_profile)
  - [x] UniversalAdapter (智能判断)
- [x] 更新 ParsedContent 基类，添加 layout_type 必填字段。
- [x] 更新 Worker 保存 layout_type 到数据库。
- [x] 更新 API Schema (ContentDetail/ShareCard/ContentUpdate)。
- [x] 生成适配器 layout_type 配置文档。

### Phase 2: 后端配置层 ✅ (2026-01-31 完成)
- [x] 实现 `SystemSettings` 表的 CRUD API。
- [x] 将硬编码的 Prompt 模板移入数据库配置。

### Phase 3: 前端重构 ✅ (2026-01-31 完成)
- [x] 前端模型添加 `layoutType/layoutTypeOverride/effectiveLayoutType` 字段。
- [x] 实现 `resolvedLayoutType` getter（用户覆盖 > 后端检测）。
- [x] 详情页路由重构：基于 `layoutType` 分发，使用 switch-case。
- [x] 保留竖屏 PortraitLayout、用户主页 UserProfileLayout 特殊处理。
- [x] 通用组件完善（新增 MediaGrid）。

### Phase 4: AI 配置界面 ✅ (2026-01-31 完成)
- [x] 前端对接 `/api/settings` 接口。
- [x] 开发主题订阅管理界面。

### Phase 5: 用户手动配置 ✅ (2026-01-31 完成)
- [x] 分享接收界面支持手动选择布局类型。
- [x] 内容编辑界面支持修改布局类型。
- [x] 详情页编辑界面支持修改布局类型。

### Phase 6: 前端平台残留清理 (新增) ✅ (2026-01-31 完成)
- [x] `rich_content.dart` 媒体展示逻辑迁移到 layoutType
- [x] `portrait_layout.dart` 平台判断迁移到 layoutType
- [x] `content_card.dart` 卡片样式迁移到 layoutType
- [x] 重命名 `twitter_landscape_layout.dart` → `gallery_landscape_layout.dart`
- [x] 重命名 `bilibili_landscape_layout.dart` → `video_landscape_layout.dart`

### Phase 7: 后端数据结构化 (新增) - 消除前端 rawMetadata 依赖 ✅ (2026-01-31 完成)
- [x] 后端统一提取 `author_avatar_url` 到顶层字段（消除前端从 rawMetadata 挖掘）
- [x] 后端统一提取 `author_url` 到顶层字段（消除前端构造 URL）
- [x] 后端统一提取 `associated_question` 到顶层字段（知乎回答关联问题）
- [x] 后端统一提取 `top_answers` 到顶层字段（知乎问题精选回答）
- [x] `markdown_content` 已通过 `description` 字段提供（无需新增字段）
- [x] API Schema 新增结构化字段，前端通过顶层字段读取数据
- [x] 创建数据库迁移脚本 `migrations/phase7_structured_fields.py`

---

## 4. 前端"擦屁股"逻辑分析

### 4.1 应由后端结构化提供的数据

| 前端位置 | 当前逻辑 | 问题 | 建议 |
|----------|----------|------|------|
| `author_header.dart:27-55` | 从 `rawMetadata['author']`, `rawMetadata['user']`, `rawMetadata['archive']['images']` 挖掘头像 | 前端硬编码多平台数据结构 | 后端统一填充 `author_avatar_url` |
| `author_header.dart:176-188` | 前端构造作者主页 URL | 平台 URL 格式分散在前端 | 后端填充 `author_url` |
| `content_side_info_card.dart:38` | 从 `rawMetadata['associated_question']` 提取 | 知乎特有结构暴露给前端 | 后端提供 `associated_question` 顶层字段 |
| `rich_content.dart:127,170` | 从 `rawMetadata['top_answers']` 提取 | 知乎特有结构暴露给前端 | 后端提供 `top_answers` 顶层字段 |
| `content_parser.dart:161-171` | 从 `rawMetadata['archive']['markdown']` 提取 | Markdown 内容应直接在 description 或新字段 | 后端统一填充 Markdown 到 `description` 或新增 `markdown_content` |
| `content_card.dart:55` | 从 `rawMetadata['archive']['dominant_color']` 提取主色调 | 应在 `cover_color` 字段 | 后端确保 `cover_color` 填充 |

### 4.2 平台命名文件分析

| 文件 | 实际用途 | 建议 |
|------|----------|------|
| `twitter_landscape_layout.dart` | Gallery 布局，用于所有图片为主的内容 | 重命名为 `gallery_landscape_layout.dart` |
| `bilibili_landscape_layout.dart` | Video 布局（仅封面），实际是简化的 Gallery | 重命名为 `video_landscape_layout.dart` 或合并到 gallery |
| `zhihu_top_answers.dart` | 知乎问题精选回答展示 | ✅ 保留 - 确实是知乎特有功能 |
| `zhihu_question_stats.dart` | 知乎问题统计展示 | ✅ 保留 - 确实是知乎特有功能 |
| `bvid_card.dart` | B站 BV 号卡片 | ✅ 保留 - 确实是 B站特有功能 |

### 4.3 必须保留的平台特有逻辑

| 逻辑 | 原因 |
|------|------|
| 知乎关联问题展示 | 知乎特有的问答关联结构 |
| 知乎精选回答列表 | 知乎特有的问题多回答聚合 |
| B站 BV 号卡片 | B站特有的视频标识符 |
| 平台术语差异（赞同/点赞、转发/分享） | 用户熟悉的平台用语 |
| 平台品牌色（B站粉色边框） | 视觉识别
