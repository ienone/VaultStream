# 设置页

## 文档状态

active

## 当前代码

- 页面：`frontend/lib/features/settings/settings_page.dart`
- tabs：连接与账号、AI 发现、推送与通知、外观与系统。
- 主要文件：`features/settings/presentation/tabs/*`

## 当前界面内容

- 页面整体是 `Scaffold` + 毛玻璃 `FrostedAppBar`。AppBar 下方是 4 个 tab：连接与账号、AI 发现、推送与通知、外观与系统；`TabBarView` 承载各 tab。页面支持通过初始 tab 参数从其他页面直接跳到指定设置区域。Debug 模式下 AppBar 右侧还提供进入引导页的按钮。

### 连接与账号 tab

- 主体是纵向 `ListView`，按 `SectionHeader` 分为服务器与通信、链接与账号、高级连接设置等区域，底部有退出登录入口。
- 服务器与通信区域包含后端 API 地址、API 访问密钥等 `ExpandableSettingTile`，展开后以内嵌表单编辑；同时提供“测试服务器连接”操作。
- 链接与账号区域提供跳转账号中心的入口，并展示平台健康只读摘要。平台摘要以 `SettingGroup` 逐平台列出健康状态、Cookie 状态和收藏同步状态。
- 平台设置区包含微博、小红书、知乎等平台的连接状态、检测状态、扫码/浏览器连接、解绑等按钮；知乎额外包含刷新指纹能力。
- 高级连接设置包含网络代理、Bilibili SESSDATA/JCT/BuVid3 等低频参数，均通过可展开表单编辑，避免默认占据页面高度。

### AI 发现 tab

- 主体是较长的 `ListView`，按自动化策略约束、AI 巡逻、发现来源、收藏自动同步、内容生成、大模型引擎等区域组织。
- 自动化策略约束区域包含多个 `Switch` 和 `DropdownButton`：发现巡逻、AI 评分写入、内容理解/摘要、分发模式、Cookie 保活、收藏同步调度、禁用平台手动同步覆盖等。
- AI 巡逻区域包含兴趣画像多行文本编辑、AI 评分阈值 `Slider`、发现保留天数、收件箱清理策略等控件。
- 发现来源区域以 `SettingGroup` 展示来源列表。每条来源可启用/禁用、手动同步、点击编辑；区域底部提供添加来源按钮。
- 收藏自动同步区域按平台展示开关、速率、手动同步按钮，并提供同步间隔、单次拉取上限、重复内容策略、立即同步、最近同步任务和同步运行记录入口。
- 内容生成和大模型引擎区域包含文本模型、视觉模型、摘要模型、嵌入模型等可展开配置；展开后编辑 API Base、API Key、模型名、维度等字段，并展示 AI 能力矩阵、连通性测试和语义索引状态。

### 推送与通知 tab

- 主体为纵向 `ListView`。顶部状态横幅按 Bot 运行状态显示不同颜色和文案。
- Bot 控制区使用 `Wrap` 排列刷新状态、启动、停止、重启等按钮，窄屏下自动换行。
- 凭证与权限配置使用 `ExpansionTile` 包裹三步 `Stepper`：选择推送平台、填写凭证、配置管理员/白名单/黑名单等访问控制。
- 群组与频道管理区包含同步群组和手动新增按钮，以及群组列表。每条群组 tile 展示平台图标、显示名称、类型标签、启用开关，以及巡逻监听/分发推送两个紧凑开关。

### 外观与系统 tab

- 主体是纵向 `ListView`，按外观模式、存储与归档策略、关于与许可组织。
- 外观模式区域提供主题模式入口，点击后通过底部抽屉选择跟随系统、浅色或深色。
- 存储与归档策略区域包含自动归档远程媒体主开关；开启后展开图片归档、视频归档开关，以及 WebP 质量、图片数量限制、视频数量限制、视频最大字节数等高级参数。
- 关于与许可区域提供开源许可页入口，底部居中展示应用名称和版本信息。

### 弹出界面与确认

- 连接与账号 tab 会打开扫码/浏览器登录 `InteractiveLoginDialog`，退出登录使用 `AlertDialog` 二次确认。
- AI 发现 tab 使用来源编辑对话框新增/编辑发现源；收藏同步预览、同步运行记录、单次运行详情也通过 `AlertDialog` 展示。
- 推送与通知 tab 的手动新增群组使用 `BotChatDialog`。
- 外观模式选择使用底部 `ModalBottomSheet`；开源许可使用系统 `showLicensePage`。

## 承担职责

- 管理全局配置。
- 提供低频设置项。
- 提供到账号中心、自动化等页面的入口。

## 不承担职责

- 不承担账号中心主流程。
- 不展示完整任务运行记录。
- 不承载复杂收藏同步工作流。
- 不应把未实现策略占位暴露为可配置项。

## 与其他页面交互

- 可从账号中心、自动化页、动态页跳转到特定设置 tab。
- 推送配置与自动化/分发队列相关。
- 媒体归档配置影响详情页媒体可用性。

## 后端/API 关联

- 读取接口：`GET /api/v1/settings`、`GET /api/v1/settings/{key}`、`GET /api/v1/ai/capabilities`。
- 写入接口：`PUT /api/v1/settings/{key}`、`DELETE /api/v1/settings/{key}`、AI 连通性测试、推送目标测试。
- 后台任务：设置项会影响同步、解析、媒体归档、分发和 Agent。

## 当前问题

- 设置页连接 tab 与账号中心重复问题见 `../../issues/frontend-account-entry-responsibility-duplication.md`。
- 设置页和自动化页暴露收藏同步 placeholder 策略的问题见 `../../issues/frontend-favorites-sync-placeholder-strategy-leak.md`。
- UI 层直接执行 API 写操作的问题见 `../../issues/frontend-ui-layer-api-write-boundary.md`。
- 前端控制面与后端自动化策略缺口见 `../../issues/frontend-control-policy-gaps.md`。

## 尚未实现 / 计划扩展

- 无本页单独计划；设置页只保留低频配置的目标边界以 `../../issues/frontend-account-entry-responsibility-duplication.md` 和 `../../issues/frontend-favorites-sync-placeholder-strategy-leak.md` 为准。
