# VaultStream 架构审计报告

**日期:** 2026-02-21
**审计对象:** 全栈 (Backend: Python/FastAPI, Frontend: Flutter)
**审计重点:** 前后端一致性、数据契约、冗余逻辑、僵尸模块、过度设计与技术债。

## 1. 核心发现摘要

VaultStream 目前处于功能快速迭代后的稳定期，架构整体清晰（Clean Architecture），但随着平台适配器（尤其是知乎）的增加，"通用适配器"（Universal Adapter）的设计理念受到了侵蚀。后端模型中出现了平台特有的字段泄漏，前端为了配合这些字段也引入了硬编码逻辑。此外，分发引擎的重算逻辑在数据量增长后存在性能隐患。

## 2. 前后端一致性与数据契约

### 2.1 平台特有数据的"泄漏"与契约断层
**问题描述:** 
设计初衷是将平台特有数据封装在 `raw_metadata` (JSON) 中以保持通用性。但在演进中出现了两个极端：
1.  **字段泄漏:** 知乎特有的 `associated_question` 和 `top_answers` 被提升到了 `Content` 数据库主表列和前端 `ContentDetail` 模型中，破坏了通用架构。
2.  **契约臃肿:** `raw_metadata` 包含了大量未经清洗的平台原始响应（如完整的 HTML、Base64 碎片、冗余追踪码），这些数据在 API 传输中造成了巨大的带宽浪费。

**建议 (三层数据契约架构):**
- **标准化核心层 (Standardized Core):** 强制适配器在解析阶段将点赞、播放、评论等指标映射到主表的 `like_count`, `view_count` 等通用字段，禁止仅存储在 `extra_stats` 中。
- **结构化扩展层 (Structured Extensions):** 引入 `extensions` JSONB 字段。适配器负责将平台特性解析为“UI 模式组件”（如 `parent_context`, `sub_items`），前端仅识别组件模式而非平台逻辑。
- **存档存储层 (Archive Storage):** `raw_metadata` 仅用于后端审计和二次解析，**彻底从 API 响应中剥离**，实现传输脱敏与减负。

**影响:**
- **解耦 UI 逻辑:** 前端不再判断 `if (isZhihu)`，而是根据 `extensions` 中的组件类型进行渲染。
- **性能飞跃:** API 响应体积预计可减少 80% 以上。

### 2.2 布局类型解析逻辑重复
**问题描述:**
"有效布局类型"（Effective Layout Type）的计算逻辑在前后端并存：
- **Backend:** `app.services.content_presenter` (逻辑：User Override > System Detection > Default)
- **Frontend:** `ShareCard.resolvedLayoutType` (逻辑同上)

**影响:**
- **维护成本:** 修改默认逻辑需要同时修改两端。
- **一致性风险:** 若后端更新了检测逻辑，前端可能因缓存或逻辑未同步而展示错误的布局。

**建议:**
- **Backend Authority:** 完全依赖后端返回的 `effective_layout_type` 字段，前端移除 `resolvedLayoutType` getter，仅作纯展示。

## 3. 冗余逻辑与代码重复

### 3.1 标签规范化 (Tag Normalization)
**问题:**
- `ContentService._normalize_tags` (backend/app/services/content_service.py) 包含分割、去重逻辑。
- `app.distribution.decision._normalize_tags` (backend/app/distribution/decision.py) 包含类型检查和清洗逻辑。
- 前端在提交 `ShareRequest` 时也有可能进行简单的处理。

**建议:**
- 提取 `app.utils.tag_utils` 模块，统一后端所有的标签处理逻辑。

## 4. 僵尸模块与清理对象

### 4.1 废弃的迁移脚本
在 `backend/tools/` 下发现大量一次性迁移脚本，应归档或删除：
- `migrate_bilibili.py`
- `migrate_m3.py`
- `migrate_zhihu.py`
这些脚本在系统初始化或特定版本升级后已无用处，留在源码中干扰视线。

### 4.2 潜在的未引用代码
- `backend/app/distribution/matcher.py` 在目录结构中未找到，但在某些旧文档或引用中可能残留。
- `backend/app/distribution/engine.py` 中的 `refresh_queue_by_rules` 方法对全量 `PARSE_SUCCESS` 内容进行遍历，在数据量大时是性能杀手。

## 5. 设计与演进压力

### 5.1 硬删除 (Hard Delete) vs 数据留存
当前 `ContentService.delete_content` 执行的是物理删除（Hard Delete），包括级联删除 `ContentSource` 和 `PushedRecord`。
- **风险:** 用户误删后无法恢复；推送历史丢失，可能导致重复推送（如果重新采集）。
- **建议:** 引入 `is_deleted` 软删除机制，或者将删除的数据移入 `archived_contents` 表，保留 URL 指纹以防重复采集。

### 5.2 分发引擎的扩展性
`DistributionEngine.match_rules` 采用的是 "Loop all rules" 的策略。虽然对于单用户系统（< 100 rules）性能可以接受，但 `refresh_queue_by_rules` 遍历所有内容则不可持续。
- **建议:** 改为事件驱动（Event Driven）。仅在 Rule 更新时，针对该 Rule 的条件构建 Query 查询受影响的 Content，而不是遍历所有 Content。

## 6. 重构设计方案 (Refactoring Plan)

### 第一阶段：清理与规范化 (Immediate)
1.  **归档脚本:** 建立 `backend/scripts/archive`，移动所有 `migrate_*.py` 脚本。
2.  **统一标签逻辑:** 创建 `backend/app/utils/tags.py`，合并所有标签清洗逻辑。
3.  **前端减负:** 移除 Flutter 中 `ShareCard` 和 `ContentDetail` 的 `resolvedLayoutType` 逻辑，直接使用 API 返回字段。

### 第二阶段：数据模型修正与契约重定义 (Medium Term)
1.  **引入扩展组件:**
    - 给 `Content` 表增加 `extensions` JSONB 列。
    - 废弃 `Content.associated_question` 和 `top_answers` 物理列。
2.  **适配器重构:**
    - 更新适配器接口，强制在 `parse` 阶段输出标准化的 `extensions` 结构。
    - 确保 `archive_metadata` (原 `raw_metadata`) 仅包含必要存档，不含 Base64 等冗余。
3.  **API 减负:**
    - 修改 Pydantic Schema，从 `ContentDetail` 及其子类中移除 `raw_metadata` 字段。
    - 增加 `extensions` 字段映射。
4.  **软删除引入:**
    - 给 `Content` 表增加 `deleted_at` 字段，更新 `delete_content` 为逻辑删除，保留 URL 指纹防止重复采集。

### 第三阶段：性能优化 (Long Term)
1.  **优化分发引擎:**
    - 重写 `refresh_queue_by_rules`，使用 SQL `WHERE` 子句直接定位受影响的 `Content`，避免应用层遍历。
    - 引入规则指纹（Rule Hash），仅当规则逻辑变化时触发重算。

---
**总结:**
VaultStream 核心架构稳固，但随着业务复杂度增加，特定的业务逻辑开始侵入通用模型。及时收敛这些"特例"（尤其是知乎相关逻辑），回归 `raw_metadata` + `Adapter` 的通用处理模式，是保持系统长期可维护性的关键。
