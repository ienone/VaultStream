# 后端模块：发现与候选信息流

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/discovery.py`
- Adapters: `backend/app/adapters/discovery/*`
- Tasks: `backend/app/tasks/discovery_sync.py`、`backend/app/tasks/discovery_cleanup.py`
- Patrol: `backend/app/services/patrol_service.py`

## 功能

- 同步发现源。
- 存储候选内容和状态。
- 支持候选内容进入收藏库或被忽略。
- 可选进行 AI 巡逻评分。

## 不承担职责

- 不管理正式收藏内容的长期编辑。
- 不直接配置平台账号登录。
- 不直接执行分发推送。

## 实现逻辑

发现源同步把外部来源内容写入 discovery/contents 相关状态字段，并用 `ContentDiscoveryLink` 保留一个内容与多个发现源的关系。候选列表返回来源正文预览、全部关联来源名称和类型；预览只是来源材料，不伪装成 AI 摘要。巡逻评分根据兴趣配置对候选项赋分，并决定是否可见或忽略。

单条候选动作支持收录、忽略、稍后处理和恢复为可见。`snoozed` 是独立持久状态，默认动态流不返回，只有稍后列表显式请求该状态；恢复是明确的 `visible` 状态转换，不通过本地假恢复掩盖后端状态。批量动作复用同一状态机。

发现源质量测试返回具名诊断 contract；前端 provider 将 `run_id/status/ok/elapsed_ms` 与候选统计解析为 typed result，页面不再直接读取动态 map。来源同步、删除和候选批量动作也已有命名响应并进入 OpenAPI 门禁。

## 测试

长期回归与临时验收边界见 [验证策略](../testing.md)。本模块其余行为在变更时针对性验收，不保留逐方法测试清单。

## 与其他模块交互

- contents: 候选内容可转为正式收藏内容。
- config-system: 发现源 enabled、巡逻评分、清理策略来自配置。
- agent: Agent 可能读取发现相关数据。

## 对应前端

- `../../frontend/pages/dashboard.md`

## API 接口

详见 `../api.md` 的 discovery/system 相关端点。

## 配置与策略

- 发现源 `enabled` 应约束定时同步、手动同步和 Agent 工具入口。
- 巡逻评分、清理策略和同步间隔来自系统设置。

## 当前问题

- 用户控制面与后端策略修复记录：`../../issues/archive/frontend-control-policy-gaps.md`
- 已归档的动态页迁移说明与统计概览问题：`../../issues/archive/frontend-dashboard-scope-creep.md`

## 尚未实现 / 计划扩展

候选浏览、收录、忽略、稍后处理、恢复和两个列表的分页读取已经进入动态信息流，不恢复独立收件箱。事件变化、来源偏好和更完整的主动探索仍待后续功能切片。
