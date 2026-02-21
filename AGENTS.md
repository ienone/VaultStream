# VaultStream 开发执行规范（skill.md）

> 目标：确保每次代码改动都可追踪、可验证、可交付。

## 0. 版本演进策略（当前项目约束）

- 当前项目未公开发布：默认不保留旧逻辑兼容层。
- 进行功能替换时，直接删除旧逻辑并落地新逻辑，不做双轨并存（如 `archive_metadata` 全面替代 `raw_metadata`）。
- 若涉及数据结构变更，必须同步新增数据库迁移文件（`backend/migrations/`）。
- 文档只描述当前实现，不写“弃用说明/兼容说明/历史对比说明”。

## 1. Python 环境与命令基线

- Python 解释器固定使用：根目录 `.venv/python.exe`
- 后端相关命令统一从仓库根目录执行，并显式使用该解释器。
- **后端测试/运行命令：**
  - 测试：`cd backend && ../.venv/python.exe -m pytest tests/`
  - 启动：`cd backend && ../.venv/python.exe -m uvicorn app.main:app --reload`

## 2. 前端开发命令基线

- **Flutter/Dart：**
  - 测试：`cd frontend && flutter test`
  - 生成代码：`cd frontend && dart run build_runner build` (模型修改后必执行)
  - 静态分析：`cd frontend && flutter analyze`
  - 格式化：`cd frontend && dart format lib/`

## 3. 标准修改流程（每次任务都遵循）

1. **明确需求边界**：先定义本次只改哪些功能，不做无关改动。
2. **定位影响范围**：后端、前端、接口、数据结构、数据库迁移、文档是否联动。
3. **先小步修改再验证**：单文件/单模块完成后立即做局部检查。
4. **全链路验证**：至少做与本次功能直接相关的分析或测试。
5. **补齐文档与注释**：代码和文档同步更新，避免“代码新、文档旧”。
6. **按功能拆分提交**：每个 commit 只包含一个清晰功能点。

## 4. 技术选型与规范

- **后端架构**：FastAPI + SQLite (WAL mode)。路由 `routers/` -> 服务 `services/` -> 仓库 `repositories/` -> `models.py`。
- **前端架构**：Flutter 3.10+ + Riverpod (Generator)。
- **数据契约**：使用 `ParsedContent` V2 结构（含 `archive_metadata`, `context_data`, `rich_payload`）。
- **代码风格**：
  - **Python**: PEP 8，强类型标注，Loguru 日志，绝不使用 `print`。
  - **Dart**: Effective Dart，Freezed 模型，`gap` 替代 `SizedBox` 间距。

## 5. 提交规范

- 一个 commit 只做一件事（如“迁移到新元数据结构”、“修复详情页缩进”）。
- 使用语义化前缀：`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`。
- 提交前必须通过 `flutter analyze` (前端) 或 `py_compile` (后端)。

## 6. 文档与测试同步

满足任一条件必须更新：
- API 响应结构或数据库字段变化。
- `models.py` 字段增删。
- 业务流程（如分发逻辑）变更。

---
*注：本项目文档只描述当前有效实现，不保留任何弃用逻辑描述。*
