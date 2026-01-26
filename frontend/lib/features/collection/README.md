# Collection Feature 模块

此模块负责应用的核心内容展示，包括收藏列表、不同平台内容的详情展示、过滤搜索以及内容管理。

## 目录结构

```text
lib/features/collection/
├── collection_page.dart          # 收藏列表主页面 (瀑布流/网格展示)
├── content_detail_page.dart      # 内容详情容器页 (负责响应式布局分发)
├── models/                       # 数据模型
│   ├── content.dart              # ShareCard/ContentDetail 核心模型
│   └── header_line.dart          # 详情页目录索引模型
├── providers/                    # 状态管理 (Riverpod)
│   ├── collection_provider.dart  # 核心收藏数据加载与同步
│   ├── collection_filter.dart    # 过滤与分类逻辑
│   └── search_history.dart       # 搜索历史管理
├── utils/                        # 业务逻辑与解析
│   └── content_parser.dart       # 核心解析类：处理 Markdown、媒体预览、统计格式化等
└── widgets/                      # 组件库
    ├── list/                     # 列表页相关组件 (Card, Grid)
    ├── detail/                   # 详情页相关组件
    │   ├── layout/               # 响应式布局：Article, Twitter, Bilibili, Portrait 等
    │   ├── components/           # 详情页颗粒化组件 (Author, Stats, RichContent)
    │   └── gallery/              # 媒体全屏展示
    ├── dialogs/                  # 业务对话框 (添加/编辑/过滤)
    └── common/                   # 通用业务组件 (Skeleton, ErrorView)
```

## 核心逻辑说明

### 1. 响应式详情页分发

`content_detail_page.dart` 根据 `constraints.maxWidth` 和 `detail.contentType` 决定使用哪种布局：

- **宽屏 (>800px)**: 进入 `Landscape` 模式，侧边展示统计和目录。
- **窄屏**: 进入 `PortraitLayout` 模式，流式展示内容。

### 2. 内容解析 (ContentParser)

负责处理不同平台（B站、知乎、Twitter等）的差异化数据映射：

- 将 HTML/特定格式 转换为 Markdown。
- 提取并匹配本地缓存的媒体资源（Local First）。
- 计算并生成目录索引。

### 3. 动态配色系统

后端提供封面主色调接口，前端依据主色调生成 Material 3 `ColorScheme`，使详情页具备沉浸式的主题感，然后设置了依据可见性回退到默认配色的机制。
