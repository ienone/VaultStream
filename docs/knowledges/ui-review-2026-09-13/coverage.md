# 覆盖矩阵

[返回主报告](README.md) · [逐项分析](pages.md) · [原图索引](image-index.md)

## 路由入口（22 个）

来源：[app_router.dart](../../../frontend/lib/routing/app_router.dart)。同一路由内部状态另计；未将 query 或内容 ID 当成新路由。

| 路由 | 截图分支 / 图组 |
|---|---|
| `/connect` | 连接入口 · 01 |
| `/onboarding` | 四步向导 · 02–03 |
| `/home` | 待收录 / 稍后 / 事件 · 04–05 |
| `/collection` | 常规 / 搜索 / 选择 / 筛选 / 批量 / 网络中断采样（非错误终态） · 06、50–51 |
| `/collection/:id` | 10 类模板，解析保护，详情菜单 · 07–15 |
| `/collection/:id/edit` | 编辑 · 14 |
| `/automation` | 总览 · 16 |
| `/automation/sync` | 平台策略 / 最近记录 / 预览 · 17 |
| `/automation/distribution` | 队列 / 规则导航 · 18 |
| `/automation/distribution/history` | 历史无真实发送记录 · 18 |
| `/automation/distribution/rules/new` | 新建 · 19 |
| `/automation/distribution/rules/:ruleId` | 编辑 / 高级 / 消息样式 · 19–20 |
| `/automation/processing` | 解析后处理 · 21 |
| `/accounts` | 平台列表 / 手动凭据 · 22、24 |
| `/accounts/:platform` | Bilibili / 知乎，登录样例 · 23–24 |
| `/settings` | 7 分区、展开编辑、许可列表及正文 · 25–33 |
| `/search` | 初始 / 无结果 / 全部 / 事件 / 时间点 · 34–36 |
| `/agent` | 会话 / 引用 / 工具 / 确认面板 / 菜单 · 37–38 |
| `/notifications` | 消息及菜单 · 39 |
| `/tasks/:runId` | 成功 / 失败 / 运行中 / 技术详情 · 40–41 |
| `/events/:id` | 时间线 / 编辑 / 关系 · 42–44 |
| `/player` | 空态 / 视频 / 倍速 / 时间点 / 横屏 · 45–47 |

## 按状态取证

| 图组 | 审查单元 | 原图状态 ID | 证据形态 |
|---|---|---|---|
| 01 | [连接入口](pages.md) | connect | 1280×900 + 390×844 |
| 02 | [初始设置：AI 与通知](pages.md) | onboarding-ai、onboarding-notification | 1280×900 + 390×844 |
| 03 | [初始设置：账号与完成](pages.md) | onboarding-accounts、onboarding-finish | 1280×900 + 390×844 |
| 04 | [动态：待收录](pages.md) | home | 1280×900 + 390×844 |
| 05 | [动态：稍后与事件](pages.md) | home-snoozed、home-events | 1280×900 + 390×844 |
| 06 | [收藏库与局部搜索](pages.md) | collection、collection-search | 1280×900 + 390×844 |
| 07 | [文章：摘要与结构化正文](pages.md) | detail-1、article-structured | 1280×900 + 390×844 |
| 08 | [图文笔记与短帖](pages.md) | detail-9、detail-10 | 1280×900 + 390×844 |
| 09 | [图集与大图](pages.md) | detail-3、gallery-fullscreen | 1280×900 + 390×844 |
| 10 | [音频与视频详情](pages.md) | detail-4、detail-5 | 1280×900 + 390×844 |
| 11 | [文档阅读](pages.md) | detail-13 | 1280×900 + 390×844 |
| 12 | [聚合页与主页](pages.md) | detail-11-populated、detail-12 | 1280×900 + 390×844 |
| 13 | [书签：待解析与失败](pages.md) | detail-6、detail-7 | 1280×900 + 390×844 |
| 14 | [编辑与详情操作菜单](pages.md) | edit、detail-menu | 1280×900 + 390×844 |
| 15 | [解析候选与合并弹窗](pages.md) | parse-candidate、parse-merge | 1280×900 + 390×844 |
| 16 | [自动化总览](pages.md) | automation | 1280×900 + 390×844 |
| 17 | [收藏同步与预览](pages.md) | sync、sync-preview | 1280×900 + 390×844 |
| 18 | [分发队列与历史](pages.md) | distribution、history | 1280×900 + 390×844 |
| 19 | [新建与编辑规则](pages.md) | rule-new、rule-edit | 1280×900 + 390×844 |
| 20 | [规则高级项与消息样式](pages.md) | rule-advanced、rule-style | 1280×900 + 390×844 |
| 21 | [解析与后处理](pages.md) | processing | 1280×900 + 390×844 |
| 22 | [账号中心](pages.md) | accounts | 1280×900 + 390×844 |
| 23 | [平台详情差异](pages.md) | account-bilibili、account-zhihu | 1280×900 + 390×844 |
| 24 | [手动凭据与登录弹窗](pages.md) | account-manual、login-sample | 1280×900 + 390×844 |
| 25 | [设置导航与中等宽度](pages.md) | settings、settings-middle | 特殊宽高见图 |
| 26 | [连接设置与展开编辑](pages.md) | settings-connection、connection-expanded | 1280×900 + 390×844 |
| 27 | [AI 模型配置](pages.md) | settings-automation、model-expanded | 1280×900 + 390×844 |
| 28 | [信息来源与来源编辑](pages.md) | settings-sources、source-editor | 1280×900 + 390×844 |
| 29 | [推送与通知](pages.md) | settings-push、push-expanded | 1280×900 + 390×844 |
| 30 | [推送目标与目标弹窗](pages.md) | settings-targets、target-editor | 1280×900 + 390×844 |
| 31 | [媒体与存储](pages.md) | settings-storage、storage-expanded | 1280×900 + 390×844 |
| 32 | [外观与许可列表](pages.md) | settings-system、licenses | 1280×900 + 390×844 |
| 33 | [许可正文](pages.md) | license-reader | 1280×900 + 390×844 |
| 34 | [搜索：初始与无结果](pages.md) | search-empty、search-no-results | 1280×900 + 390×844 |
| 35 | [搜索：全部与事件](pages.md) | search、search-events | 1280×900 + 390×844 |
| 36 | [搜索：时间点](pages.md) | search-timepoints | 1280×900 + 390×844 |
| 37 | [Agent 会话与证据](pages.md) | agent、agent-evidence | 1280×900 + 390×844 |
| 38 | [Agent 工具展开与会话菜单](pages.md) | agent-tool-expanded、agent-menu | 1280×900 + 390×844 |
| 39 | [消息盒子与操作菜单](pages.md) | notifications、notification-menu | 1280×900 + 390×844 |
| 40 | [任务完成与失败](pages.md) | task-complete、task-failed | 1280×900 + 390×844 |
| 41 | [任务运行中与技术详情](pages.md) | task-running、task-technical | 1280×900 + 390×844 |
| 42 | [事件详情与编辑](pages.md) | event、event-edit | 1280×900 + 390×844 |
| 43 | [加入新事件与已有事件](pages.md) | event-add、event-existing | 1280×900 + 390×844 |
| 44 | [事件关系编辑](pages.md) | event-relation | 1280×900 + 390×844 |
| 45 | [播放器空态与视频](pages.md) | player-empty、player-video | 1280×900 + 390×844 |
| 46 | [播放器速度与时间点弹窗](pages.md) | player-speed、player-bookmark | 1280×900 + 390×844 |
| 47 | [播放器横屏](pages.md) | player-landscape | 特殊宽高见图 |
| 48 | [保存内容：链接与文本](pages.md) | capture-link、capture-text | 1280×900 + 390×844 |
| 49 | [保存文件与模板选择](pages.md) | capture-file、template-picker | 1280×900 + 390×844 |
| 50 | [收藏筛选与批量操作](pages.md) | collection-filter、collection-batch | 1280×900 + 390×844 |
| 51 | [选择状态与网络中断采样（非错误终态）](pages.md) | collection-selected、collection-failed | 1280×900 + 390×844 |
| 52 | [深色：设置与收藏](pages.md) | settings-dark、collection-dark | 1280×900 + 390×844 |
| 53 | [深色 Agent 与正文下半部](pages.md) | agent-dark、article-structured-lower | 1280×900 + 390×844 |

总计 53 个图组、194 张页面原图。settings-middle 为 900×900；player-landscape 为 844×390。其余图组与状态的精确关系以原图索引为准。
