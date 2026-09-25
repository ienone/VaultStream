# 仓库协作指南

## 需求理解与工作尺度

- 围绕用户的实际目标开展工作，区分明确要求、说明性例子和自行选择的实现方式。不得把例子的具体属性升级为需求，也不得把自己的推导写成“用户明确要求”。
- 用户通过实例指出普遍问题时，应检查并处理任务范围内的同类问题，不能只修改被点名的实例；同时避免扩展到无关领域。
- 用户纠正理解后，应重新检查受影响的判断、方案和产物，撤销误解引入的要求，不要只修改被指出的那句话。
- 根据证据作出合理推断，结论范围与证据相称。证据足以支持当前决策时就推进；只有进一步调查可能改变决策或结果时才继续，不以消除所有不确定性为前提。
- 采用完整达成目标的最简方案，使实现、调研、验证和文档的规模与任务需要及风险相称。新增复杂度和产物应有实际用途，不为假设中的需要或展示充分性而增加工作。
- 在已有授权内完成必要工作，达到目标并通过必要验证后及时结束。简化不能遗漏相关问题，也不应仅因“还能更全面、更通用”而继续扩展。

## 项目结构与模块组织

VaultStream 分为 Python 后端和 Flutter 前端：

- `backend/app/`: FastAPI 应用代码，包括 `routers/`、`services/`、`repositories/`、`adapters/`、`tasks/`、`core/`。
- `frontend/lib/`: Flutter 应用代码，按功能模块 `features/` 和共享层 `core/`、`routing/`、`theme/` 组织。
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
   - 先读取相关 `docs/plans/*.plan.md`；只有同名 `*.process.md` 实际存在时才读取 process。概念方案和尚未开始实际执行的计划不要求创建 process。
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
- 前端依赖安装：`cd frontend && flutter pub get`
- 前端代码生成：`cd frontend && dart run build_runner build --delete-conflicting-outputs`
- 前端 Web 运行：`cd frontend && flutter run -d chrome`
- 前端检查：`cd frontend && flutter analyze && flutter build web`
- Docker 服务栈：`cd backend && docker compose up -d`

在 Codex 或其他受限沙盒环境中，任何 `flutter` 或 `dart` 命令都必须申请提权并在沙盒外执行，不要在默认沙盒中直接运行。这包括但不限于 `flutter pub get`、`flutter analyze`、`flutter test`、`flutter run`、`dart run build_runner ...`。如果无法提权运行，必须在结果中明确说明未验证。本机非沙盒 Amp CLI 可直接执行；沙盒外执行不等于 sudo

## 编码风格与命名约定

- Python: 4 空格缩进，尽量使用类型标注；函数和文件使用 `snake_case`，类名使用 `PascalCase`。
- Dart/Flutter: 遵循 `frontend/analysis_options.yaml` 中的 `flutter_lints`；成员使用 `lowerCamelCase`，类型使用 `UpperCamelCase`，文件名使用 `snake_case.dart`。
- 模块职责保持聚焦：adapters 负责解析/抓取，services 编排业务逻辑，repositories 负责数据访问，routers 保持薄层。
- 前端 UI 应遵循 Material 3 expressive 风格，保持清晰层级、明确的颜色和形状选择。
- 前端页面必须实现竖屏、横屏、手机、平板和桌面下的响应式行为，并在核心页面的多个断点下验证。
- 动效应平滑且有明确目的，持续时间和曲线保持一致，避免引入卡顿或界面重叠。

## 用户界面与文案克制

- 界面只展示帮助用户阅读、理解结果或完成操作的信息。禁止将内部状态、实现细节、调试信息和开发过程解释铺在日常页面、卡片、空白处或空状态中；必要的技术诊断放到明确进入的诊断详情或日志。
- 缺少非必要内容时直接省略，不为填满界面增加占位说明。来源隐藏、删除、无权限或缺少定位时，前端按无来源处理，不展示“断点”“待溯源”“访问不了”等诊断标签。
- UI 和日志都不得填入未经证实的原因、能力宣称或开发过程解说；不能把删掉的界面噪声搬进日志。原因与操作建议须由实际状态、可复现证据或明确的外部 API 契约支持；否则只陈述失败事实。日志只保留有定位价值的事件，不记录重复心跳、正常轮询、逐项成功或推测性解释。
- 禁止空泛、拟人化、宣传式或用户难以理解的 AI 文案。提示须简短具体，说明对当前操作有用的事实或下一步；没有实际帮助就删除。必须处理的失败仍应在操作发生处明确反馈，不能用隐藏错误冒充简洁。
- 页面以主要内容为视觉中心，信息和操作按职责归类；避免重复标题、解释卡片、嵌套面板和多余层级。留白不需要填满。图文、文章和媒体布局应分别适合阅读，并充分适配竖屏与横屏，而非机械缩放同一网格。

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

## 验证规则

- 不保留或新增单元测试、实现镜像测试及对应常规测试套件。需要验证时，针对实际改动执行一次性检查或真实流程验收；完成后删除临时测试脚本，不为了测试而创建长期设施。
- 优先从用户或系统入口验证最终结果。静态分析、构建、替身调用和 HTTP 2xx 只证明各自边界，不冒充完整流程成功。
- 保留必要的结果、实际输入范围和未验证限制即可，不要求持久化一次性测试产物或追求覆盖率、测试数量。
- 后端验证使用仓库根虚拟环境 Python；Flutter/Dart 遵守上面的沙盒外执行要求。
- 外部平台和账号态验收按需执行，真实副作用遵守用户授权与已有控制面。凭据和私有样本不进入 Git。

## Commit 与 Pull Request 规则

- commit 必须尽量小而聚焦，按功能、修复、文档、测试、重构等边界适当拆分。
- 不要把无关的前端、后端、文档和格式化改动混在一个 commit 中；确有必要混合时，需要在 commit 描述中说明原因。
- commit message 使用 Conventional Commit 风格，例如 `feat: ...`、`fix(frontend): ...`、`docs: ...`、`chore: ...`。
- commit 标题和正文优先使用中文，除非项目已有自动化或外部协作明确要求英文。
- PR 描述也优先使用中文，至少包含：
  - 简洁摘要和动机。
  - 关联 issue / plan / task（如有）。
  - 验证证据，例如构建、`flutter analyze` 和实际流程结果。
  - UI 变更截图或录屏（如适用）。

## 安全与配置

- 使用 `backend/.env.example` 作为配置模板，不要提交真实 `.env`。
- API token、bot 凭据、keystore 和其他秘密信息不得进入 Git。
- 涉及外部副作用的功能必须尊重用户可见控制面，例如同步、推送、Agent 工具、媒体抓取和解析 worker 不应绕过已有策略边界。
