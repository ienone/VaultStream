# 仓库协作指南

## 项目结构与模块组织

VaultStream 分为 Python 后端和 Flutter 前端：

- `backend/app/`: FastAPI 应用代码，包括 `routers/`、`services/`、`repositories/`、`adapters/`、`tasks/`、`core/`。
- `backend/tests/`: 后端 pytest 测试，包括 `test_api/`、`test_adapters/`、`test_tasks/` 等。
- `frontend/lib/`: Flutter 应用代码，按功能模块 `features/` 和共享层 `core/`、`routing/`、`theme/` 组织。
- `frontend/test/`: Flutter 单元测试和 widget 测试。
- `docs/`: 当前文档体系，包括前端、后端、计划、问题和知识库文档。
- `scripts/`: 工具脚本。

## 背景信息读取规则

当任务依赖项目背景、文档结构、产品意图、职责边界、已有计划或已知问题时，先按任务类型读取入口文档，再按需打开具体文档和代码。不要默认批量读取所有文档。

1. 文档体系相关任务：
   - 先读 `docs/README.md`。
   - 再按需读取对应目录的 README、plan、process、issue 或 knowledge 文档。
2. 前端相关任务：
   - 先读 `docs/frontend/README.md`。
   - 如果涉及路由、导航、页面归属或入口职责，再读 `docs/frontend/navigation.md`。
   - 修改页面前，读取对应的 `docs/frontend/pages/*.md`。
   - 修改共享组件或交互前，读取对应的 `docs/frontend/components/*.md`。
3. 后端相关任务：
   - 先读 `docs/backend/README.md`。
   - 修改 router、service、repository、task、model 或 schema 前，读取对应的 `docs/backend/modules/*.md`。
   - 涉及 API 或数据库时，按需读取 `docs/backend/api.md`、`docs/backend/database.md`。
4. 计划相关任务：
   - 读取相关 `docs/plans/*.plan.md` 和同名 `*.process.md`。
   - 如果计划已完成或归档，检查 `docs/plans/archive/`。
5. 问题修复或审校任务：
   - 读取相关 `docs/issues/*.md`。
   - 如果问题已关闭或归档，检查 `docs/issues/archive/`。
6. 平台适配器或外部平台行为相关任务：
   - 读取相关 `docs/knowledges/adapters/*.md` 或其他 `docs/knowledges/` 文档。

文档用于建立上下文，当前代码和可重复验证结果仍是最终事实来源。若文档和代码不一致，必须指出不一致，不要静默按过期文档实现。

## 构建、测试与开发命令

- 后端依赖安装：`cd backend && pip install -r requirements-dev.txt`
- 本地启动后端（Windows）：`cd backend && ./start.ps1`
- 本地启动后端（Linux/macOS）：`cd backend && ./start.sh`
- 后端测试：`.venv\Scripts\python.exe -m pytest backend/tests -q`
- 前端依赖安装：`cd frontend && flutter pub get`
- 前端代码生成：`cd frontend && dart run build_runner build --delete-conflicting-outputs`
- 前端 Web 运行：`cd frontend && flutter run -d chrome`
- 前端检查：`cd frontend && flutter analyze && flutter test`
- Docker 服务栈：`cd backend && docker compose up -d`

在 Codex 或其他受限沙盒环境中，任何 `flutter` 或 `dart` 命令都必须申请提权并在沙盒外执行，不要在默认沙盒中直接运行。这包括但不限于 `flutter pub get`、`flutter analyze`、`flutter test`、`flutter run`、`dart run build_runner ...`。如果无法提权运行，必须在结果中明确说明未验证。

## 编码风格与命名约定

- Python: 4 空格缩进，尽量使用类型标注；函数和文件使用 `snake_case`，类名使用 `PascalCase`。
- Dart/Flutter: 遵循 `frontend/analysis_options.yaml` 中的 `flutter_lints`；成员使用 `lowerCamelCase`，类型使用 `UpperCamelCase`，文件名使用 `snake_case.dart`。
- 模块职责保持聚焦：adapters 负责解析/抓取，services 编排业务逻辑，repositories 负责数据访问，routers 保持薄层。
- 前端 UI 应遵循 Material 3 expressive 风格，保持清晰层级、明确的颜色和形状选择。
- 前端页面必须实现竖屏、横屏、手机、平板和桌面下的响应式行为，并在核心页面的多个断点下验证。
- 动效应平滑且有明确目的，持续时间和曲线保持一致，避免引入卡顿或界面重叠。

## 重构与兼容策略

- 当用户要求替换、收敛、重构或删除旧实现时，默认应移除旧路径，而不是保留 fallback、兼容层、双路径或运行时选择逻辑。
- 只有存在明确外部兼容需求、数据迁移窗口、灰度发布要求，或用户明确要求时，才允许保留兼容层。
- 不允许为了“保险”保留无人负责的旧逻辑。
- 不允许让新旧逻辑长期并存，并通过运行时条件、字段猜测或异常吞掉来选择路径。
- 如果删除旧逻辑存在风险，应先指出风险和验证方式，而不是自行添加隐藏 fallback。

## API 使用规则

- 构造或调用 API 前，必须先读取真实 contract，包括后端 router、request/response schema、service 返回值、现有前端 API client、相关测试和 `docs/backend/api.md`。
- 不得根据猜测写字段名、状态码、成功条件、错误处理或兼容分支。
- 不得写 `response == "1"`、`status == "ok"`、`data != null` 这类未被 contract 证明的判断。
- 如果响应格式不清晰，先补充或修正文档、类型或测试，再实现调用逻辑。
- 如果后端返回值确实混乱，应把问题记录到 `docs/issues/`，不要在前端或调用方静默兼容多个猜测格式。
- API 封装应复用项目已有 client、鉴权、错误处理、分页和序列化约定，不要随手新增平行封装。

## 测试规则

- 后端使用 `pytest`，默认启用覆盖率配置（`backend/pytest.ini`、`.coveragerc`）。
- 后端测试必须使用仓库根目录的虚拟环境 Python，不使用全局或系统解释器。
  - Windows 示例：`.venv\Scripts\python.exe -m pytest backend/tests -q`
  - 这样可以避免环境漂移。
- 外部平台或集成测试必须标记 `@pytest.mark.integration`。
- 测试应放在变更附近。例如新增 API 路由时，应在 `backend/tests/test_api/` 下补测试。
- Flutter 变更应在 `frontend/test/unit` 或 `frontend/test/widget` 中补充 `flutter test` 覆盖。
- 正式、可重复的后端测试必须放在 `backend/tests/` 下，确保新测试文件默认能被 Git 追踪。
- 本地探针、真实平台调试脚本、依赖 cookie/数据库的检查和捕获输出应放在 `backend/manual_tests/`。该目录被忽略，不得作为 CI 或常规验收依据。
- 不要把单个后端测试文件名加入 `.gitignore`。如果文件不适合常规收集，应移出 `backend/tests/`，或改成带显式 skip/marker 的可重复测试。

## Commit 与 Pull Request 规则

- commit 必须尽量小而聚焦，按功能、修复、文档、测试、重构等边界适当拆分。
- 不要把无关的前端、后端、文档和格式化改动混在一个 commit 中；确有必要混合时，需要在 commit 描述中说明原因。
- commit message 使用 Conventional Commit 风格，例如 `feat: ...`、`fix(frontend): ...`、`docs: ...`、`chore: ...`。
- commit 标题和正文优先使用中文，除非项目已有自动化或外部协作明确要求英文。
- PR 描述也优先使用中文，至少包含：
  - 简洁摘要和动机。
  - 关联 issue / plan / task（如有）。
  - 验证证据，例如 `pytest`、`flutter analyze`、`flutter test`。
  - UI 变更截图或录屏（如适用）。

## 安全与配置

- 使用 `backend/.env.example` 作为配置模板，不要提交真实 `.env`。
- API token、bot 凭据、keystore 和其他秘密信息不得进入 Git。
- 涉及外部副作用的功能必须尊重用户可见控制面，例如同步、推送、Agent 工具、媒体抓取和解析 worker 不应绕过已有策略边界。
