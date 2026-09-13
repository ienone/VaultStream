# 后端模块：收藏同步

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/system.py`
- Service: `backend/app/services/favorites_sync_service.py`
- Fetchers: `backend/app/adapters/favorites/*`
- Task: `backend/app/tasks/favorites_sync.py`
- Config: `backend/app/services/config_service.py`

平台注册表及能力声明归属 `adapters/favorites/__init__.py`。目前注册知乎收藏夹、小红书收藏笔记、Bilibili 本人视频收藏夹、微博个人收藏和 X 个人书签。微博复用 SUB 登录，通过移动 config 识别账号、桌面 all_fav 分页；X 使用显式保存的 auth_token/ct0，在服务端浏览器中复用当前网页请求。微博和 X 均保留页内偏移；账号变化会拒绝旧游标。注册支持代表已实现接入，不代表真实私有账号验收通过。集合身份由 fetcher 传入统一 FavoriteItem，导入写入 ContentSource 的 client_context；同一内容来自不同集合时保留各自来源。

平台状态使用 `FavoritesPlatformStatusResponse`，包含类型明确的 `capabilities`：supported、scope、pagination、collection_metadata、authentication、limitation。available 表示当前执行基础是否可用，authenticated 不替代实际抓取时的平台校验。前端按能力关闭未接入平台的开关、同步和账号入口；支持平台仍复用现有策略与账号页。

## 功能

- 同步平台收藏夹或收藏内容。
- 预览同步结果。
- 记录同步 run 和失败项。
- 支持重试 run、单项重试和批量重试。

## 不承担职责

- 不承担账号登录主流程。
- 不展示完整 UI 状态。
- 不直接决定内容分发。

## 实现逻辑

系统配置决定启用平台和同步策略。同步任务调用平台 fetcher 获取收藏项，再按重复策略写入内容库。正常同步、单项重试和批量重试共用 `FavoritesSyncTask.import_items`，最终均通过 `ContentService` 的 canonical URL 去重与 `ContentSource` 流水写入；部分失败仍保留逐项结果。

只有本轮导入没有失败项时才提交下一游标，包括显式保存 None 清除已到末页的旧游标。导入失败时保留当前页游标，并在结果 next_cursor 中返回实际保留值，下次可重新处理该页；已成功内容继续按重复策略去重，不因失败越过未导入收藏。

小红书明确声明 `has_more=true` 时必须返回非空且向前变化的字符串游标，否则报 `invalid_pagination`，保留持久化游标，不能把分页异常当作末页。

同步状态、手动策略、预览、trigger、run retry、单项 retry 和批量 retry 由 `FavoritesSyncService` 统一编排；router 不再直接创建协程、检查平台认证或调用内容导入。动作使用命名响应且所有执行路径稳定返回 `run_id`。`202` 只表示任务已受理，单项/批量同步执行的 `200` 则同时返回导入、跳过和失败统计。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- accounts-auth: 依赖平台 Cookie/浏览器认证。
- contents: 同步结果写入内容库。
- events-tasks: 同步 run 和失败项需要可观测。
- agent: Agent 工具可能触发收藏导入，必须受同一策略控制。

## 对应前端

- `../../frontend/pages/automation.md`
- `../../frontend/pages/tasks.md`

## API 接口

- `GET /api/v1/favorites-sync/status`
- `POST /api/v1/favorites-sync/sync`
- `POST /api/v1/favorites-sync/preview`
- `POST /api/v1/favorites-sync/runs/{run_id}/retry`
- `POST /api/v1/favorites-sync/items/retry`
- `POST /api/v1/favorites-sync/items/batch-retry`

## 配置与策略

- 平台 enabled、同步范围、重复策略、取消收藏策略和手动触发策略来自系统配置。
- 定时入口检查 scheduler policy；单平台手动、run retry、item retry 和 batch retry 在创建执行性 run 或导入前检查 `favorites_platform_manual`。默认禁用返回统一 `409`；已有 `force`/允许禁用平台手动同步配置只沿原 contract 生效。
- `scope=all` 每次只读取当前启用平台，不从历史 run 恢复已禁用平台。

## 历史决策

- [已关闭问题的历史决策](../../issues/archive/README.md)。

## 尚未实现 / 计划扩展

收藏同步 run 的摘要、平台结果和失败项处理已迁入统一任务页；自动化页只保留发起、策略、平台状态和最近运行入口。

2026-09-13 后续已获账号授权，Bilibili 本人收藏实际读取两条并返回续接游标及集合身份；此小批正向验收不等于全量或长期会话验收。

## 重扫幂等与解析入队恢复

默认合并按内容、同步来源、平台和收藏夹识别同一远端来源：已成功处理的同一收藏重扫不再追加相同来源，也不改写内容版本；不同收藏夹仍保留独立来源。skip仍跳过已存在的完成内容。两种策略均会恢复未处理/解析失败内容的队列交接，避免“内容已提交但入队失败”在下一次被重复检查掩盖；已删除内容不因同步恢复。

单项和批量失败项重试携带collection_id/collection_title，复用正常同步来源名称，重试关系保留在运行账本和client_context。已完成的单项再次重试返回同一内容成功结果，不重复来源、不误报500。知乎收藏夹和条目页必须提供列表及布尔is_end，缺失或非末页空列表明确失败，不推进游标。
