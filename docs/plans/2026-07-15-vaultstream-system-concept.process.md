# VaultStream 系统构想与演进蓝图执行记录

## 状态

in_progress

## 对应 Plan

- `./2026-07-15-vaultstream-system-concept.plan.md`

## 实际执行记录

- 2026-07-15：根据产品讨论创建系统级构想，覆盖捕获、存档、模板、富媒体、搜索/RAG、主动探索、事件聚合、Agent、模型成本、UI、账号扩展和 Rust 远景。
- 2026-07-15：明确细分文章、图文笔记、短帖子、帖子串、图集、对话/消息包、视频、音频、文档和书签，不再使用万能“帖子/媒体条目”。
- 2026-07-15：取消僵硬的物理数据分层，改为从来源证据、当前内容、可重建结果和保留策略理解数据。
- 2026-07-15：补充音视频跨页面播放、仅音频、横竖屏适配、画中画和 Android 原生媒体控制。
- 2026-07-15：补充跨模板事件聚合、带证据的 Agent 综合和供应商侧 Prompt Cache 设计意识。
- 2026-07-16：先执行仓库卫生清理，移除陈旧辅助目录、误生成目录、敏感备份和 Gmail 反编译产物；Animeko 参考仓库保留。
- 2026-07-16：从 Gmail 反编译资源中提取可复用的自适应界面组织经验，形成 `../knowledges/ui/gmail-adaptive-interface-reference.md`。
- 2026-07-16：修复根目录测试数据/日志的生成来源、测试临时目录、integration 标记、conftest 重复装载和 pytest 临时路径问题。
- 2026-07-16：收敛 `.gitignore`、README、计划索引、过期页面链接和 RAG 评估脚本路径。
- 2026-07-16：按用户反馈将系统构想从实现规格改写为概念蓝图，删除字段名、伪 contract、组件选型和过细工程参数，同时保留关键产品决策。
- 2026-07-16：检查旧数据库与 1.77 GB 媒体副本，按正文长度、媒体形态、特殊平台和既有 RAG 基准抽取 57 条代表性内容，保留 48.1 MB 完整媒体样本并删除其余媒体。
- 2026-07-16：将测试数量虚高、价值密度低和运行成本高的问题记录为独立 issue，后续按业务风险重构测试套件。
- 2026-07-16：将前端 IA 计划从 582 行收敛为只描述有效目标、页面职责、自适应原则和验收边界的计划，已完成操作继续保留在同名 process。
- 2026-07-16：将 API 与数据库文档改为短入口加领域分册；OpenAPI 端点清单独立生成并继续由 CI 校验。
- 2026-07-16：重写页面文档规范和七份页面现状文档，移除 Widget 树、像素和 provider 罗列，保留用户任务、状态、自适应行为和问题边界。

## 与初始计划的偏离

- 用户要求在继续修改构想前先清理辅助目录和仓库卫生，因此本轮加入了代码、测试和文档修复，不再是纯文档任务。
- 旧脚本、历史迁移、手工测试输出和 RAG 评估媒体副本曾短暂移入仓库外隔离目录；完成核验后已永久删除，不保留无人维护的备份树。
- RAG 媒体副本经数据库引用映射和代表性抽样后完成处理；全量媒体、原始完整数据库和一次性评估报告均已删除，只保留精简样本及可重复执行的评估输入。
- 构想仍为 `draft`；本轮完成的是边界和表达方式收敛，不代表实施优先级已经确定。

## 验证结果

- 后端聚焦测试：队列并发测试 `4 passed`；任务、媒体和调度聚焦测试 `76 passed`。
- CI 等价后端测试：`763 passed, 4 skipped, 9 deselected`，覆盖率 64%；根 `data/` 和根 `logs/` 未复发。
- integration 测试已与常规测试分离；真实 LLM、知乎和外部图片代理不再进入默认/CI 测试。
- 依赖审计未发现已知漏洞；Bandit 无高危或中危问题，剩余为低危提示。
- SQLite 完整性与外键一致性检查通过；重复索引和一个缺失外键索引留待独立数据库优化计划处理。
- 精简样本数据库包含 57 条内容和 405 个媒体对象；810 个原图/缩略图文件全部存在，现有 5 条 RAG ground truth 继续保持 `Recall@5 = 1.0`、`Recall@10 = 1.0`。
- 文档重构后 Markdown 链接缺失数为 0，状态字段缺失数为 0；前端页面文档不再命中 Widget、provider、像素和具体布局类扫描。
- OpenAPI 生成清单与当前应用一致，127 个端点全部通过校验；从仓库根目录和 CI 使用的 `backend/` 工作目录运行均通过。
- 数据库 schema gate 通过：schema version 29、完整性正常、外键问题 0、FTS 及 3 个触发器正常。
- 虚拟环境未安装 Ruff，未执行 Ruff；两个文档工具脚本已通过 `py_compile`。
- `git diff --check` 通过；`docs/frontend/pages/tasks.md` 不再被 Windows 大小写规则意外忽略。
- 本轮没有修改 Flutter 代码，因此未运行 `flutter analyze` 或 `flutter test`。

## 主要产出

- 更新：`docs/plans/2026-07-15-vaultstream-system-concept.plan.md`
- 更新：`docs/plans/2026-07-15-vaultstream-system-concept.process.md`
- 更新：`docs/plans/README.md`
- 新增：`docs/knowledges/ui/gmail-adaptive-interface-reference.md`
- 新增：`docs/knowledges/eval/legacy-dataset-media-sample.md`
- 新增：`docs/issues/backend-test-suite-value-density.md`
- 清理：陈旧辅助目录、旧脚本/迁移/测试输出、误生成数据与日志、Gmail 反编译目录和敏感临时文件。
- 精简：旧数据库媒体由约 1.77 GB 收敛为约 48.1 MB 的代表性样本，验证完成后删除完整数据库备份。

## 后续问题

- 需要确认 Android 分享、Telegram Bot、QQ Bot 和桌面入口的实施顺序。
- 需要从系统蓝图拆出独立 UI 审计与重构计划，结合 Animeko 参考和真实多断点截图推进。
- 需要为存档数据模型、模板样本、富媒体播放、搜索/RAG、AI 调用治理和事件聚合分别建立实施计划。
- 需要按 `backend-test-suite-value-density.md` 审查现有测试的业务风险覆盖、重复度和执行成本。
