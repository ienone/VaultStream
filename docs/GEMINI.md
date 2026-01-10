# VaultStream 项目开发规范（基于项目实况调整）

本文档基于仓库当前实现对原有 Gemini 参考规范做出必要调整，方便接手开发者快速对齐。

## 1. 架构概述
- Frontend: Flutter（支持 Mobile / Web / Desktop）
- Backend: Python + FastAPI（路由位于 `backend/app/api.py`）
- Database: 默认使用 SQLite（项目内有数据库适配层，位于 `backend/app/db_adapter.py`）
- Feature 组织: `lib/features/{feature}/[models|providers|widgets|pages]`（当前已有 `collection`、`review`、`dashboard` 等模块）

说明：仓库中保留若干 SQL 迁移脚本（`backend/migrations/`），部分脚本包含 PostgreSQL 专用语法（如 JSONB）。当前代码默认使用 SQLite 适配器；如需切换到 PostgreSQL，需要复现/实现 PostgreSQLAdapter 并按需运行相应迁移。

## 2. 视觉规范（Material 3 Expressive）
- 主题入口：请在 `frontend/lib/theme/app_theme.dart` 中查看与修改全局 `ColorScheme`、`Typography` 与 `Shape`。
- 风格要点：
  - 强调更鲜明的色块与对比度，但避免过度饱和导致可读性下降。可通过 `primaryContainer` / `surfaceContainer` 控制富表达面板。
  - 统一大圆角样式（建议卡片/容器圆角 16 左右），把圆角与间距抽成 Theme 常量以便复用。
  - 动效：使用轻量的进入/退出与交互反馈（Fade/Scale/AnimatedOpacity 等），尽量使用 Flutter 的隐式动画组件以降低实现复杂度。

实践：在全局主题中统一定义动效时长（例如 200–400ms）与阴影等级以保证一致性。

## 3. 自适应与断点
- 项目当前断点设置（参考 `frontend/lib/core/layout/responsive_layout.dart`）：
  - Mobile breakpoint: 800
  - Desktop breakpoint: 1200
  - 列数根据宽度动态计算（函数 `ResponsiveLayout.getColumnCount`）
- 组件要求：
  - 列表类视图在宽屏下应以 Grid（瀑布/网格）方式展示，项目中 `collection` 使用 `MasonryGridView` 并通过 `ResponsiveLayout.getColumnCount` 控制列数。
  - 手机端对话优先用 `showModalBottomSheet`，桌面/大屏使用 `showDialog` 或自定义浮层（以键盘与焦点行为一致为准）。

## 4. 后端对齐协议（项目实际）
- 分页：后端多数列表接口接收 `page` 与 `size` 参数，并返回结构包含 `items`、`total`、`page`、`size`、`has_more`（参见 `backend/app/api.py` 中 `/contents` 与 `/cards`）。前端应按此格式解析并实现懒加载/下拉刷新。
- 鉴权：后端要求 `X-API-Token` Header，或使用 `Authorization: Bearer <token>`（优先使用 `X-API-Token`）。前端的 `api_client` 必须在请求中注入此 header 并在 401/403 时做友好提示。
- 错误处理：后端通过 FastAPI 的 `HTTPException` 返回状态码与 `detail`。前端应统一在 `api_client.dart` 解析并转为用户提示（SnackBar / 对话框），并对网络异常提供重试路径。

## 5. 数据库与迁移
- 默认：SQLite（由 `backend/app/db_adapter.py` 的 `SQLiteAdapter` 管理）。适配器已设置若干 PRAGMA（WAL、cache、mmap 等）以提高本地性能。
- 搜索：项目优先尝试 FTS5 全文索引（若可用），没有时降级到 ILIKE。请在 `backend/app/api.py` 的搜索逻辑中查看实现细节。
- 迁移策略：
  - 所有结构变更必须在 `backend/migrations/` 新增脚本并在测试环境验证。
  - 注意：仓库中存在 PostgreSQL 专用迁移（例如 JSONB 相关）。如果目标环境为 PostgreSQL，请先实现/启用 PostgreSQL 适配器并使用对应迁移脚本；否则不要在 SQLite 上直接执行 JSONB 脚本。

## 6. 前端实现与复用建议
- 以 `collection` 页面为模板（路径：frontend/lib/features/collection/collection_page.dart）复用以下要素：
  - 列表/网格布局、懒加载/分页、骨架占位、错误/空状态处理、卡片点击导航逻辑。
  - 抽象可重用组件：`ContentCard`、`SkeletonCard`、分页加载/节流逻辑、网络图片缓存组件。
- 提交新页面时，确保：
  - 使用 `ResponsiveLayout` 控制列数与卡片宽度；
  - 所有外部资源（图片/视频）使用缩略/代理接口并开启缓存；
  - 所有 `Controller` / `StreamSubscription` 在 `dispose()` 中释放。

## 7. 性能基线与优化要点
- 列表滚动：使用 `ListView.builder` / `GridView.builder` / `MasonryGridView` 的 builder 版本；避免在 `build` 中创建大对象或控制器。
- 图片与媒体：优先使用后端生成的缩略图或 `proxy` 接口（项目提供本地代理 `GET /api/v1/media/{key}`，见 `backend/app/api.py`），并在前端使用磁盘缓存（如 `cached_network_image`）。
- 骨架与动画：使用轻量动画（`AnimatedOpacity`、`AnimatedSize`、简易 shimmer 或基于 `AnimationController` 的呼吸效果），避免多个复杂动画同时运行。

## 8. CI/CD、运行与验证
- 迁移：任何数据库结构变更都必须伴随 `backend/migrations/` 下的新脚本并在测试环境验证。对于生产环境，先执行备份与回滚验证。
- 启动：后端通过 `backend/start.sh` 或 docker-compose 启动；前端通过 Flutter 常规方式运行。

## 9. 交接与优先任务（给接手者的建议）
1. 本地复现：先启动后端与前端并确认 `collection` 页面可正常加载与分页。
2. 抽取复用：将 `collection` 的分页、骨架、卡片抽为共享组件库，供其它列表页面复用。
3. API 差异表：列出新页面所需字段与后端实际返回字段的差异，必要时向后端提出小范围 API 扩展（保持向后兼容）。
4. 迁移准备：任何数据库 schema 变更前准备好迁移脚本与回滚步骤并在 dev 环境测试。
5. 性能验证：在低端设备上进行滚动/切换基线测试，优先修复明显卡顿点（图片解码、网络阻塞、过度重绘）。

---
快速定位：
- `frontend/lib/features/collection/collection_page.dart` (示例页面)
- `frontend/lib/core/layout/responsive_layout.dart` (断点与列数策略)
- `frontend/lib/theme/app_theme.dart` (主题配置)
- `backend/app/api.py` (后端路由与分页/鉴权逻辑)
- `backend/app/db_adapter.py` (当前数据库适配器：SQLite)

如需我把此文件提交为 PR（包含运行/测试步骤和变更清单），我可以继续创建分支、提交并打开 PR。是否继续？
