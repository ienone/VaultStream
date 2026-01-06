# TODO 开发清单（VaultStream：收藏为主 + 合规分享推送）

> 原则：
> 1) 私有存档（Full Archive） 与 分享输出（Share Card） 严格隔离  
> 2) 解析与平台差异收敛到 -Adapter + 标准化 Schema-  
> 3) “推过不再发”以 `pushed_records` 为准，所有推送必须可追溯、可重放（但默认不重复）  
> 4) 先闭环再优化：入口→解析→入库→检索→分发

---

## 里程碑 M0：项目基础与可运行闭环（本地）✅
- [x] 仓库结构（backend/app/bots/docs）
- [x] ~~Docker Compose（PostgreSQL + Redis + backend）~~ → **轻量化架构（SQLite + 本地存储）**
- [x] 健康检查 `/health`（backend）
- [x] 统一配置与密钥管理（dev/prod；env 校验；敏感信息不入库不出日志）
- [x] 基础可观测：结构化日志（request_id / content_id / task_id）
- [x] **架构简化**：移除PostgreSQL/Redis/MinIO依赖，仅保留适配器抽象层

---

## 里程碑 M1：收藏入口（Input）与去重模型
目标：任何来源 URL 都能被“稳定收下”，并可追踪来源与去重。

- [x] 入口协议（文档即接口契约）
  - [x] `POST /shares`：url、tags、source（app/web/bot）、note、is_nsfw、client_context（可选）
  - [x] 鉴权方案：先简单 Token（Header），后续可扩展用户体系
- [x] URL 规范化与去重
  - [x] URL 净化：去 utm 等追踪参数、短链还原、统一 scheme/host
  - [x] 去重键：`canonical_url` + `platform`（必要时加 platform_id），避免重复入库
- [x] 数据模型（收藏核心）
  - [x] `contents`：canonical_url、platform、platform_id（可空）、title（可空）、tags、is_nsfw、status、raw_metadata(JSONB)、created_at
  - [x] `content_sources`（可选但推荐）：记录每次“分享触发”的来源（source、tags_snapshot、note、timestamp）
- [x] 状态机落地（以解析为中心）
  - [x] `unprocessed -> processing -> pulled|failed -> archived`
  - [x] 明确每个状态的进入条件与回滚策略（失败记录落库 + reshare 触发重试；人工修复/管理端后置）
  - [x] 最小回滚实现已完成：在 `contents` 表增加 `failure_count`、`last_error`、`last_error_type`、`last_error_detail`、`last_error_at`；worker 写入失败信息；`POST /shares` 对 `failed` 状态触发重试；`ContentDetail` 暴露失败摘要字段

---

## 里程碑 M2：解析流水线（Process）与 Adapter 体系
目标：平台差异全部沉到 Adapter，流水线稳定、可重试、可观测。

- [x] Adapter 抽象（强约束输出）
  - [x] 输入：canonical_url / platform_id（可选）
  - [x] 输出：标准字段（title/author/published_at/media[]/text/cover）+ `raw_metadata`
  - [x] 错误分类：可重试/不可重试/需要登录凭证
- [x] Pipeline（队列 + Worker）
  - [x] ~~Redis 队列任务格式版本化~~ → **SQLite Task 表队列**（使用SELECT FOR UPDATE SKIP LOCKED）
  - [x] 幂等：同一 content_id 重复任务不造成脏写（基于乐观锁/更新时间戳）
  - [x] 重试策略：指数退避 + 最大次数 + dead-letter（可选）
- [ ] 平台优先级
  - [x] Bilibili：视频/动态（封面、作者、简介、统计字段）
  - [x] Twitter/X：正文、媒体原图\视频、作者信息
  - [ ] 小红书/知乎：先做通用提取（正文+主图+作者），再定制
  - [ ] 逐步完善：微博、抖音、酷安、YouTube 等
- [ ] 协同解析（可选：降低反爬成本）
  - [ ] 方案 A：移动端上传 cookie/token（强加密/短期存储/可撤销）
  - [ ] 方案 B：移动端直接抓取“已展开页面”快照（HTML/关键字段）供后端结构化

---

## 里程碑 M3：私有存档能力（Storage）与索引检索 ✅
目标：库内“能找得到、翻得动、查得快”。

- [x] 媒体存储：本地文件系统 + SHA256内容寻址 + 2级目录分片
- [x] 图片转码：WebP格式转换（可配置质量，默认80）
- [x] 媒体访问增强
  - [x] 媒体代理 API (静态流式输出，支持 Range)
  - [x] 自动化缩略图生成 (图片压缩)
- [x] SQLite 索引优化
  - [x] `(platform, created_at)`
  - [x] `status`
  - [x] `tags`（JSON字段索引）
  - [x] `raw_metadata` 常用路径（已映射到主表字段）
  - [x] 基于 SQLite FTS5 的全文搜索集成
- [x] 管理辅助 API
  - [x] 全局标签列表及计数 API (GET /tags)
  - [x] 标签合并与重命名支持 (通过 PATCH /contents 实现基础修改)
  - [x] 队列状态实时统计 (Pending/Processing/Failed 计数)
  - [x] 仪表盘聚合统计 (按平台、时间轴、容量占用)
- [x] 查询 API（给 Web/App/Bot 复用）
  - [x] 条件：tag/platform/status/is_nsfw/时间范围/关键字
  - [x] 分页：offset 分页，支持 page/size
  - [x] 排序：默认按时间倒序
- [x] 内容详情 API (给 Web/App/Bot 复用，便于可视化)
  - [x] 基本字段：title/author/published_at/tags/is_nsfw/status/created_at/updated_at
  - [x] 媒体列表：类型/url/本地代理 url/宽高/大小
- [x] 修改 API
  - [x] 改 tags（覆盖）
  - [x] 改标题/备注
  - [x] 标记 NSFW
  - [x] 触发重解析 (可通过修改 status)
  - [x] 删除（可以实现软/硬删）
- [ ] 语义检索（后置但要预留）
  - [ ] `embeddings` 表：content_id、model、vector、updated_at
  - [ ] 入库/更新触发：解析完成或摘要完成后生成 embedding

- [x] 文档记录：
  - [x] API 说明 ([docs/API.md](docs/API.md))
  - [x] 示例请求响应 (已集成在文档中)
  - [x] 数据库索引与 FTS5 说明 ([docs/DATABASE.md](docs/DATABASE.md))

---

## 里程碑 M4：合规分享出库（Share Card）与分发规则（Output）✅
目标：对外只输出"合规卡片"，永不直接外发私有原始信息。

- [x] 分享卡片（Share Card）定义与优化
  - [x] 统一数据结构：title、summary、optimized_media[]（使用 M3 代理/压缩图）、source_url、tags
  - [x] **预览 API**：`GET /contents/{id}/preview` 提供各平台适配后的渲染效果
  - [x] **禁止泄露**：严格剥离原始全文、敏感元数据（如 Cookie 信息）、内部文件路径
- [x] 分发引擎（Distribution Engine）
  - [x] **分发规则模型 `distribution_rules`**：tag -> targets[]（TG/QQ/…）、enabled、nsfw_policy、approval_required、template_id
  - [x] **审批流管理**：在 `contents` 增加 `review_status` (pending/approved/rejected)；支持按规则自动审批
  - [x] **异步推送任务**：Worker 增加 `distribute` 任务类型，处理平台限流、重试退避
- [x] 推送历史与一致性(一处推过不再推)
  - [x] 推送历史记录表 `pushed_records`：content_id、target_id、message_id、push_status、唯一约束保证不重复推送
  - [x] 规则匹配策略：DistributionEngine 实现优先级匹配、NSFW策略、频率限制
- [x] 安全闸门
  - [x] NSFW 强制分流：不合规目标强制拦截（硬失败）
  - [x] 发送回执确认：Bot 发送成功后调用 `POST /bot/mark-pushed` 同步记录

**已完成文档**：[M4 分发规则与审批流 API 文档](docs/M4_DISTRIBUTION.md)

---

## 里程碑 M5：机器人与推送实现（TG 优先）✅
目标：既能"拉取"，也能"自动推送"，并且支持 Markdown 渲染与多媒体合并。

- [x] **命令系统（8个命令）**
  - [x] `/start` - 欢迎与快速指引
  - [x] `/help` - 详细帮助文档
  - [x] `/get` - 随机获取待推送内容（兼容 `/get 标签` 旧用法）
  - [x] `/get_tag <标签>` - 按标签筛选拉取
  - [x] `/get_twitter` - 拉取 Twitter 平台内容
  - [x] `/get_bilibili` - 拉取 B站平台内容
  - [x] `/list_tags` - 查看所有可用标签及计数
  - [x] `/status` - 系统运行状态（健康检查 + 队列统计）
  
- [x] **消息渲染优化**
  - [x] HTML 格式化输出（标题、作者、标签、统计数据、源链接）
  - [x] 多媒体处理（Media Group 支持，最多10个媒体）
  - [x] 优先使用原始 CDN URL（Twitter/B站等），降级使用本地存储
  - [x] 自动文本截断（caption 1024字符，message 4096字符）
  - [x] 封面图自动补充（无媒体时使用 cover_url）
  
- [x] **错误处理与降级机制**
  - [x] 媒体组发送失败 → 降级为单个媒体
  - [x] 单个媒体发送失败 → 降级为纯文本
  - [x] 超时重试（read_timeout/write_timeout 分级配置）
  - [x] 结构化日志（user/content_id/platform/耗时追踪）
  
- [x] **推送记录与去重**
  - [x] 发送后自动调用 `POST /bot/mark-pushed` 标记
  - [x] 基于 `pushed_records` 表确保"推过不再推"
  - [x] 支持多目标独立追踪（不同频道/群组分别记录）

- [x] **配置与连接管理**
  - [x] 代理支持（HTTP/SOCKS5，自动检测环境变量）
  - [x] 连接池复用（httpx.AsyncClient 持久化）
  - [x] 初始化验证（Bot连接、频道访问、后端API健康检查）
  - [x] 优雅关闭（资源清理回调）

- [x] **自动推送模式（Push Mode）** ✅
  - [x] Worker 触发：响应 M4 分发引擎的推送任务（`distribute` 类型）
  - [x] 定时轮询：按分发规则检查 `approved` 且未推送的内容
  - [x] 批量推送：支持一次处理多条内容（防止频道刷屏）
  - [x] 推送限流：Telegram API 频率限制适配（20条/分钟）
  
- [x] **消息交互增强** ✅
  - [x] InlineKeyboard 按钮：`[标记NSFW] [重解析] [删除]`
  - [x] CallbackQuery 处理：按钮点击后的操作回调
  - [ ] 消息编辑：推送后更新内容时同步修改频道消息
  - [ ] 消息撤回：删除内容时自动撤回频道消息（需存储 message_id）
  
- [x] **用户权限控制** ✅
  - [x] 白名单/黑名单机制（限制命令使用者）
  - [x] 管理员权限：部分命令仅管理员可用（如删除、重解析）
  - [ ] 频道管理员验证：确保 Bot 有发送权限

### 待优化项 🚧  

- [ ] **MarkdownV2 升级**（可选）
  - [ ] 改用 MarkdownV2 格式（当前 HTML 已足够）
  - [ ] 代码块、引用、列表等富文本样式优化
  - [ ] 不使用emoji
  
- [ ] **多目标支持**（后续扩展）
  - [ ] 多频道/群组配置（从分发规则读取 targets）
  - [ ] 不同目标独立推送策略（NSFW 分流、模板差异）
  - [ ] QQ Bot/Discord/企业微信等其他平台适配器（后续再考虑，暂时搁置）

---

## 里程碑 M6：Web 管理端（先“能用”，再“好用”）
目标：管理内容、查找内容、配置分发规则、观察推送结果。

- [ ] 基础鉴权（Token 或 Basic Auth 起步）
- [ ] 内容列表/详情（瀑布流或列表）
  - [ ] 筛选：tag/platform/status/is_nsfw/时间
  - [ ] 操作：改 tags、标记 NSFW、触发重解析、手动归档
- [ ] 分发规则 CRUD
- [ ] 推送记录查询（按 content_id/目标/时间）
- [ ] 导入/导出（JSON/CSV；用于迁移与备份）

- [ ] 推送分析与监控
  - [ ] 推送成功率统计（按平台/时间段）
  - [ ] 失败原因分类（网络超时/API限流/内容违规）
  - [ ] 推送历史查询接口（支持 Web 端展示）
  - [ ] 告警通知：连续失败时通知管理员

---

## 里程碑 M7：移动端 Flutter（Share Target / 日常入口）
目标：把“收藏”做成系统级动作，减少操作成本。

- [ ] Flutter 工程初始化（Material 3 Expressive）
- [ ] Share Target
  - [ ] Android：接收分享文本/URL；iOS：Share Extension（如需要）
  - [ ] 预设分类（Cos/Tech/Meme）+ 自定义 tag + NSFW 勾选 + note
- [ ] 提交与反馈
  - [ ] 提交后显示解析状态（轮询/推送均可）
  - [ ] 本地草稿与失败重试

---

## 里程碑 M8：AI 摘要与增强（可选增量）
目标：提升“可读性/可检索性”，但不破坏合规边界。

- [ ] 摘要生成（对 Share Card 生效）
  - [ ] 输入：标题/正文（若合规）/关键信息；输出：短摘要 + 关键标签建议
  - [ ] 缓存与版本：避免重复消耗
- [ ] 标签建议（半自动）
  - [ ] 建议不自动落库，默认人工确认或在规则中选择自动
- [ ] 多语言与翻译（如目标频道需要）

---

## 里程碑 M9：运维、安全、合规落地
- [ ] 访问控制与最小权限
  - [ ] 管理端与 API 分级权限（至少区分“只读/管理”）
  - [ ] 凭证（cookie/token）加密存储、可撤销、过期策略
- [ ] 反爬策略与风控SQLite 数据库文件 + 本地媒体目录备份
  - [ ] 限速、代理池（如需要）、失败熔断
- [ ] 备份与恢复演练（PG 定期备份 + 恢复验证）
- [ ] 文档：NSFW 边界与使用规范（清晰写明“私有存档 vs 合规分享”）

---

## 里程碑 M10：测试与质量（贯穿式）
- [ ] Adapter 单测（URL 识别/ID 提取/解析输出 schema 校验）
- [ ] Pipeline 集成测试（队列 -> worker -> DB -> API）
- [ ] 回归用例：去重、幂等、push 不重复、NSFW 分流硬失败
- [ ] 性能基线：入库吞吐、查询分页、推送批量

--- 

## 当前优先级建议（2026年1月）
1) ~~M1：入口协议 + 去重键 + health + 基础索引~~ ✅
2) ~~M2：Adapter 输出 schema 强约束 + pipeline 幂等/重试~~ ✅
3) ~~M3：存储优化 + 全文搜索 + 管理 API~~ ✅
4) ~~M4：分发规则与审批流~~ ✅
5) ~~M5 基础：TG Bot 命令系统 + Media Group + 推送去重~~ ✅
6) **M5 自动推送（本周重点）**：
   - Worker 分发任务处理
   - 定时轮询 + 批量推送
   - InlineKeyboard 交互按钮
7) **M6 Web 管理端（下周开始）**：
   - 内容列表/详情（瀑布流）
   - 分发规则 CRUD 界面
   - 审批操作面板
   - 推送历史查询
