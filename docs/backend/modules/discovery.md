# 后端模块：发现与收件箱

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

发现源同步把外部来源内容写入 discovery/contents 相关状态字段。巡逻评分根据兴趣配置对候选项赋分，并决定是否可见或忽略。

## 测试

- `backend/tests/test_api/test_discovery_api.py`
- `backend/tests/test_api/test_discovery_sources.py`
- `backend/tests/test_tasks/test_discovery_tasks.py`
- `backend/tests/test_patrol_service.py`
- `backend/tests/test_discovery_models.py`

## 与其他模块交互

- contents: 候选内容可转为正式收藏内容。
- config-system: 发现源 enabled、巡逻评分、清理策略来自配置。
- agent: Agent 可能读取发现相关数据。

## 对应前端

- `../../frontend/pages/discovery.md`
- `../../frontend/pages/dashboard.md`

## API 接口

详见 `../api.md` 的 discovery/system 相关端点。

## 配置与策略

- 发现源 `enabled` 应约束定时同步、手动同步和 Agent 工具入口。
- 巡逻评分、清理策略和同步间隔来自系统设置。

## 当前问题

发现源 enabled 对手动同步、Agent 工具和后台任务的约束需要统一确认，避免前端开关不能控制后端副作用。

## 尚未实现 / 计划扩展

发现统计应从动态页迁移到收件箱域内展示。
