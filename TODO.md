# TODO 开发清单（基于《更好的分享系统》设计）

## 阶段 0：项目基础设施与仓库结构
- [x] 创建代码仓库基础结构（如 backend / app / bots / docs 等目录）
- [x] 约定基础技术栈与代码规范（Python 版本、依赖管理工具、格式化 & lint 方案等）
- [x] 搭建本地开发环境（`.env` 模板、配置文件示例）
- [x] 搭建 Docker / Docker Compose（PostgreSQL + Redis + 后端）
- [x] 编写基础 README（如何启动开发环境）

## 阶段 1：后端核心骨架（FastAPI）
- [x] 初始化 FastAPI 项目结构（分层：routers / services / repositories / models / schemas）
- [x] 接入 PostgreSQL（使用 async ORM/Query 工具，如 SQLAlchemy + asyncpg 或 Tortoise ORM）
- [x] 接入 Redis（做任务队列 & 去重缓存的基础包装）
- [x] 设计基础配置体系（区分 dev / prod 环境，使用 Pydantic Settings 或类似方案）
- [ ] 提供健康检查接口（`/health`）

## 阶段 2：数据模型与状态机
- [x] 设计内容实体表 `contents`（含 content_id、platform、url、tags、status、created_at 等）
- [x] 为跨平台元数据设计 JSONB 字段（如 `raw_metadata jsonb`）
- [x] 设计并创建 `pushed_records` 表（记录 content_id、target_platform、timestamp 等）
- [x] 明确内容状态机：`Unprocessed -> Pulled -> Distributed -> Archived`（当前实现到 Distributed；Archived 预留）
- [ ] 为常用字段创建索引（platform、tags、status、created_at）
- [ ] 模型/Schema 对齐：将 `platform_id`、通用互动字段、`extra_stats` 与 `schemas.py` / API 返回字段统一

## 阶段 3：采集与解析流水线基础能力
- [x] 设计「平台适配器 Adapter」接口（统一抽象：输入 URL / 标识，输出标准化结构）
- [x] 实现通用 URL 净化模块（短链接还原、去除追踪参数 `?utm_*` 等）
- [x] 实现第一个实际平台适配器（Bilibili）
- [x] 实现异步解析流水线：
  - [x] 解析任务入队（Redis 队列）
  - [x] Worker 消费任务，调用对应平台 Adapter
  - [x] 将解析结果写入 PostgreSQL（JSON 元数据 + 标准化字段）
- [ ] 为流水线编写基础单元测试 / 集成测试样例
- [ ] 进一步解耦解析逻辑（将 URL 识别 / ID 提取 / 清洗逻辑沉到 utils/adapter，避免多处重复）

## 阶段 4：输入端（Trigger）最小能力
- [x] 设计后端接收链接的 API（`POST /shares`，参数包含 url、tags、source 等）
- [x] 实现简单 Web 调试页面，用于手动提交 URL 触发采集
- [ ] 设计未来移动端（Flutter）Share Target 的对接协议（请求体字段、鉴权方式），暂用文档形式描述

## 阶段 5：自动化分发层（机器人 / Output）
- [x] 选择并搭建首个机器人运行环境（Telegram Bot）
- [ ] 设计「分发规则」数据结构（Tag -> 目标频道/群、是否 NSFW、启用状态等）
- [x] 提供后端 API：按条件查询待推送内容（未推送、按 tag / 平台筛选）
- [x] 机器人侧实现：
  - [x] 指令拉取 `/get [tag]`
  - [ ] 主动轮询模式（定时从后端拉取未推送内容）
  - [x] 图文混排消息发送格式（带封面/图片 + 文本 + 链接）
- [x] 实现“推过不再发”逻辑：
  - [x] 发送成功后回调/调用后端接口，写入 `pushed_records` & 更新内容状态
  - [x] 确保同一内容不会对同一目标多次推送

## 阶段 6：展示与检索（可与机器人并行推进）
- [ ] 后端生成基础 RSS Feed（按 Tag 或频道区分，RSS 2.0）
- [ ] 实现简单 Web 展示页（瀑布流/列表，分页展示）
- [ ] 接入基础鉴权（Basic Auth 或简单 Token）以保护 Web 展示端
- [ ] 支持按 Tag / 平台 / 时间过滤检索

## 阶段 7：内容合规与 NSFW 分流
- [x] 设计标签体系与 NSFW 标记字段（`is_nsfw`）
- [ ] 后端在分发规则中强制检查：NSFW 内容禁止发送至 QQ，只允许发送到 TG 特定频道
- [ ] Web 展示端对 NSFW 内容做访问控制（登录后可见 / 独立区域）
- [ ] 为涉及 NSFW 流程撰写说明文档，明确边界和使用规范

## 阶段 8：移动端 Flutter App（MD3）
- [ ] 初始化 Flutter 项目，启用 Material Design 3（颜色方案、基础组件）
- [ ] 设计并实现 Share Target 接入（iOS / Android 分平台配置）
- [ ] 完成最小交互流程：
  - [ ] 从其他 App 分享链接 -> 唤起本 App
  - [ ] 选择预设分类（Cos/Tech/Meme 等）
  - [ ] 可添加自定义标签 & NSFW 勾选
  - [ ] 提交后调用后端 `POST /shares` 接口
- [ ] 预留未来功能位（历史记录页、编辑标签等，但在 MVP 阶段可不实现）

## 阶段 9：监控、日志与运维
- [ ] 统一日志格式（请求日志、任务日志、分发日志）
- [ ] 为关键任务添加简单监控指标（任务失败率、解析耗时、推送数量等）
- [ ] 编写基础运维文档（如何部署、如何更新、如何排查常见错误）

## 阶段 10：迭代与扩展
- [ ] 按优先级逐步接入更多平台适配器（微博、知乎、小红书等）
- [ ] 优化解析质量（提取更丰富的结构化字段）
- [ ] 丰富 Web 展示端（收藏、分组、批量操作等）
- [ ] 丰富机器人交互（多步对话、搜索历史内容等）
