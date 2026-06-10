# 后端现状文档中的当前问题缺少 issue 追踪

## 状态

active

## 现象

- 多个 `docs/backend/modules/*.md` 和 `docs/backend/database.md` 在 `## 当前问题` 或 `## 尚未实现 / 计划扩展` 中直接写缺陷、风险或整改方向，但没有链接到 `docs/issues/`。
- 例子包括 favorites sync 策略绕过、run 详情重复展示、分发边界拆分、发现源 enabled 策略、`system.py` 拆分、Agent 工具策略接入、账号健康状态边界等。
- 这些内容既不是纯现状事实，也不是带验收标准的 plan，容易被后续 agent 当作“当前实现”或无约束待办继续扩写。

## 影响范围

- 文档：`docs/backend/modules/*`、`docs/backend/database.md`、`docs/issues/*`。
- 后端模块：config-system、favorites-sync、events-tasks、distribution、discovery、agent、accounts-auth、media。
- 用户影响：问题追踪分散，修复优先级和验收方式不清晰，后续自动修改容易重复制造同类 slop。

## 复现方式

1. 运行 `rg -n "当前问题|尚未实现|需要|待验证|后续" docs/backend/modules docs/backend/database.md`。
2. 检查命中的“问题”是否链接到 `docs/issues/`。
3. 对比 `docs/README.md` 的写作规则，确认问题应进入 `issues/`，现状文档只写当前代码真实行为。

## 根因分析

- 文档重构后已经建立了现状/计划/问题边界，但后端模块页仍保留部分待整改内容。
- 缺少文档 lint 或人工清单来保证 `当前问题` 只链接 issue，不直接承载问题正文。
- 部分问题跨度较大，之前被塞进模块文档而没有拆为独立 issue。

## 关联代码

- 主要是文档治理问题；抽样关联代码包括：
- `backend/app/routers/system.py`
- `backend/app/routers/discovery.py`
- `backend/app/services/automation_policy.py`
- `backend/app/services/agent/tools/api_bridge.py`

## 关联文档

- `../README.md`
- `README.md`
- `../backend/README.md`
- `../backend/modules/favorites-sync.md`
- `../backend/modules/events-tasks.md`
- `../backend/modules/distribution.md`
- `../backend/modules/discovery.md`
- `../backend/modules/config-system.md`
- `../backend/modules/agent.md`
- `../backend/modules/accounts-auth.md`
- `../backend/database.md`

## 修复建议

- 最小修复：把后端模块页的 `## 当前问题` 改为只链接对应 issue；没有 issue 的内容先拆入 `docs/issues/`。
- 中期修复：为 `docs/backend` 增加轻量检查脚本或人工 review checklist，避免“需要/应/后续”类整改项滞留在现状章节。
- 长期修复：当 issue 关闭后，再回到模块文档更新“当前实现”事实，避免现状文档携带历史问题描述。

## 验证方式

- 自动/半自动检查：`rg -n "当前问题|需要|应|后续|待验证" docs/backend/modules docs/backend/database.md`。
- 手动验收：每个后端模块页的 `## 当前问题` 只包含 issue 链接或“无已确认问题”。
- 文档 review：确认计划性内容只存在于 `docs/plans/` 或“尚未实现 / 计划扩展”且有明确状态。
