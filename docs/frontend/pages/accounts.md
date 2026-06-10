# 账号中心

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/accounts/account_center_page.dart`
- 路由：`/accounts`
- 相关后端：`/platform-health`、`/browser-auth/*`

## 当前界面内容

- 页面整体是 `Scaffold` + 毛玻璃 `FrostedAppBar`，标题为“账号中心”，右上角提供刷新按钮。主体按平台健康 provider 的 loading/error/data 三态渲染。
- 加载态显示居中进度；错误态使用 `_LoadError` 居中 `Column`，包含错误图标、错误文本和重试按钮。

### 主体布局

- data 态主体是 `RefreshIndicator` 包裹的纵向 `ListView`，自上而下包含账号概览、Cookie 保活、平台健康卡片网格和最近收藏同步记录。
- 账号概览 `_AccountOverview` 使用 `Wrap` 排列 4 个固定宽度概览 tile：健康平台、需处理、已连接、收藏同步。每个 tile 使用图标、数值和标签的横向组合，窄屏下自动换行。
- Cookie 保活卡片使用圆角 `DecoratedBox` 和纵向 `Column`。标题行展示图标、标题和“已启用/已暂停”标签，下方能力行展示最近运行、最近失败等信息；可点击的 run 会跳转任务结果页。
- 平台卡片网格使用 `LayoutBuilder` + `GridView.builder`，宽屏约三列，中等宽度两列，窄屏一列；网格本身禁用滚动并嵌入父级 `ListView`。

### 平台健康卡片

- 每个 `_PlatformHealthCard` 使用圆角边框容器和纵向 `Column`。顶部行包含平台图标、平台名和健康状态标签。
- 卡片中部展示三类能力行：登录 Cookie、登录检测、收藏同步。每行包含状态图标、标题、副标题、最近时间或错误摘要。
- 如果平台有 issues，会在卡片内以提示文本展示，帮助用户判断是否需要重新连接或修复。
- 卡片底部使用 `Spacer` 将按钮推到底部，并用 `Wrap` 放置检测登录、重新连接、预览同步等按钮；窄屏或按钮过多时自动换行。
- 平台名称和图标覆盖知乎、小红书、Twitter、微博、Bilibili 等平台。

### 最近收藏同步

- 如果存在最近收藏同步 run，页面底部显示最近 5 条记录。每条是 `ListTile`，包含平台、状态、时间和摘要，点击跳转 `/tasks/{runId}` 查看任务结果。

### 弹出界面与入口

- “重新连接”会打开 `InteractiveLoginDialog`，用于扫码或浏览器登录。
- “预览同步”会打开 `_FavoritesPreviewDialog`。对话框顶部用 `Wrap` 展示拉取、预计新增、已存在、跳过等统计 chips，下面按平台列出预览详情和提示说明。
- 账号中心只保留账号连接、检测和轻量同步预览；完整同步策略、运行记录和失败重试应跳转自动化或任务结果页。

## 承担职责

- 作为平台账号状态和连接动作的唯一主入口。
- 展示平台可用性、认证状态和最近同步摘要。
- 引导用户修复登录失效问题。

## 不承担职责

- 不编辑分发规则。
- 不承担系统设置全量配置。
- 不展示完整分发队列。

## 与其他页面交互

- 设置页应只链接到账号中心，不重复平台健康列表。
- 自动化健康矩阵应只跳转账号中心，不重复登录/解绑主流程。
- 收藏同步可在账号卡片展示轻量入口，但完整运行详情应进入任务页或收藏同步页面。

## 后端/API 关联

- 读取接口：`GET /api/v1/platform-health`、`GET /api/v1/favorites-sync/status`。
- 写入接口：`POST /api/v1/browser-auth/session/{platform}`、`POST /api/v1/browser-auth/{platform}/check`、`POST /api/v1/browser-auth/{platform}/logout`、`DELETE /api/v1/browser-auth/{platform}`。
- 后台任务：收藏同步和 Cookie 保活状态会影响账号健康摘要。

## 当前问题

- 账号职责重复和主入口收敛问题见 `../../issues/frontend-account-entry-responsibility-duplication.md`。

## 尚未实现 / 计划扩展

- 无本页单独计划；账号中心、设置页和自动化页的职责边界以 `../../issues/frontend-account-entry-responsibility-duplication.md` 为准。
