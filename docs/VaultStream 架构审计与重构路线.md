# VaultStream 架构审计与重构路线图

## 1. 深度审计发现：核心痛点与风险

### 1.1 物理层紧耦合 (Environmental Coupling) — **已修复**
*   **硬编码 IDs**: 原本在 `constants.py` 中硬编码了预览内容的主键 ID (`6, 8, 9`)，这导致系统强绑定于特定数据库快照，迁移即失效。目前已全面改为动态统计。
*   **Enum 值与 ID 混用**: `ContentType` 曾直接使用数据库 ID 字符串作为枚举值。目前已标准化为业务语义字符串（如 `video`, `article`）。

### 1.2 类型契约断层 (Type Contract Gaps) — **部分风险待解**
*   **手动同步风险**: 前端 Dart 模型与后端 Pydantic Schema 仍通过手工镜像维护。虽然当前逻辑一致，但缺乏自动化校验流（OpenAPI）。
*   **字符串依赖风险**: 后端 Enum 存储采用全小写，前端逻辑中曾出现硬编码大小写不匹配（如 `approval_item.dart` 中的小写判断），此类隐患可能导致业务逻辑静默失败。目前已通过清理死代码和规范化 Enum 列降低风险。

### 1.3 模型臃肿与逻辑散落 — **已修复**
*   **薄模型化**: 成功将 `display_title`、`effective_layout_type` 等计算逻辑从 ORM `Content` 模型中剥离，移至独立的 `content_presenter.py`。
*   **消除冗余封装**: 重构了内容分发 payload 构建逻辑，使用 Pydantic 的 `model_validate` 替代了数百行的手动字典赋值。

## 2. 当前架构状态汇总 (Status Quo)

### 2.1 数据层
*   **ContentType 枚举**：语义化字符串定义于 `app/constants.py`。
*   **Content 模型**：仅保留数据字段定义，计算逻辑外置。
*   **Enum 序列化**：所有 `SQLEnum` 统一定义了 `values_callable`，确保数据库持久化层与 Python 模型层在大小写上严格对齐（小写存储）。

### 2.2 适配器层
*   所有平台适配器命名标准化，并完成了 `TwitterFxAdapter` 向 `TwitterAdapter` 的遗留清理。

### 2.3 分发层
*   解耦了分发逻辑与推送服务，建立了一套稳定的 `ContentPushPayload` 契约。

## 3. 重构路线执行进度

### Phase 1：解除数据锚定 ✅
*   [x] 移除 `PREVIEW_CONTENT_IDS` 硬编码，改为动态统计。
*   [x] `ContentType` 枚举值改为语义化字符串。
*   **风险提示**：生产环境需执行数据迁移脚本，确保存量内容的 `content_type` 从数字 ID 转换为字符串。

### Phase 2：类型契约一致性 ⏳
*   [x] 规范化后端 Enum 大小写。
*   [x] 前端 `ApprovalItem` 及其中的硬编码字符串逻辑清理（死代码）。
*   [ ] **待办**：引入自动化 OpenAPI 导出流。

### Phase 3：架构分层优化 ✅
*   [x] 实施“薄模型”策略，建立 `content_presenter.py`。
*   [x] 自动化推送 Payload 构建。

### Phase 4：技术债清理与回归验证 ✅
*   [x] 修正系统测试断言（解决 `redis` 字段缺失导致的报错）。
*   [x] 将非标准测试脚本移至 `bench/` 目录。
*   [x] 统一适配器命名空间。
*   [ ] **待办**：集成 RBAC 权限模型（按需）。
