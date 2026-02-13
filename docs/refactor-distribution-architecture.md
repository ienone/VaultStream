# 分发系统架构重构指南

> 本文档供 Agent 参考，用于指导 Review/Distribution 模块的解耦重构。

## 1. 现状概述

当前分发系统由三个实体构成，因分阶段开发导致职责重叠：

| 实体 | 存储位置 | 本意 |
|------|---------|------|
| **DistributionRule** | `distribution_rules` 表 | 定义匹配规则 + 分发策略 |
| **Rule.targets** | `distribution_rules.targets` JSON 列 | 规则内嵌的分发目标列表 |
| **BotChat** | `bot_chats` 表 | Bot 关联的群组/频道身份管理 |

## 2. 具体问题清单

### 2.1 死代码：BotChat 上的过滤/策略字段从未被引擎使用

分发引擎 `backend/app/distribution/engine.py` 的 `create_distribution_tasks()` 方法（L166-L205）是唯一的分发执行路径。它只做两件事：
1. 用 `Rule.match_conditions` 匹配内容
2. 遍历 `Rule.targets` JSON 获取推送目标

**以下 BotChat 字段从未被引擎读取，是功能死代码：**

| BotChat 字段 | 对应的 Rule 字段 | 说明 |
|---|---|---|
| `tag_filter` (JSON) | `Rule.match_conditions.tags` | BotChat 的标签过滤从未生效 |
| `platform_filter` (JSON) | `Rule.match_conditions.platform` | BotChat 的平台过滤从未生效 |
| `nsfw_policy` (str) | `Rule.nsfw_policy` | BotChat 的 NSFW 策略从未生效 |
| `priority` (int) | `Rule.priority` | BotChat 的优先级从未参与排序 |

**代码定位：**
- BotChat 模型定义：`backend/app/models.py` L458-L506
- 引擎匹配逻辑：`backend/app/distribution/engine.py` L22-L82
- 引擎任务创建：`backend/app/distribution/engine.py` L166-L205

### 2.2 双向松散 JSON 引用导致不一致风险

- `DistributionRule.targets` JSON 内存 `[{platform, target_id, ...}]` → 正向：Rule→目标
- `BotChat.linked_rule_ids` JSON 内存 `[rule_id, ...]` → 反向：BotChat→Rule

两者没有外键约束，没有级联删除，完全靠业务代码维护一致性。删除 Rule 后 BotChat 的 `linked_rule_ids` 仍保留已删 ID；删除 BotChat 后 Rule 的 `targets` 仍指向不存在的 target_id。

**代码定位：**
- Rule.targets 定义：`backend/app/models.py` L330
- BotChat.linked_rule_ids 定义：`backend/app/models.py` L487
- 关联/解除 API：`backend/app/routers/bot_management.py` L172-L220

### 2.3 目标定义存在于两处

Rule.targets JSON 中的 `{platform, target_id}` 与 BotChat 的 `{chat_id, chat_type}` 本质上描述同一个目标。但：
- Rule.targets 是无类型的 JSON dict，无校验约束
- BotChat 是正式的 ORM 模型，有同步/可达性等运维属性
- 两者之间没有任何引用关系（target_id 可能与 chat_id 格式不一致）

### 2.4 NSFW 策略存在于两处且值域不同

| 位置 | 字段 | 可选值 |
|------|------|--------|
| DistributionRule | `nsfw_policy` | `allow`, `block`, `separate_channel` |
| BotChat | `nsfw_policy` | `inherit`, `allow`, `block`, `separate` |

值域不同（`separate_channel` vs `separate`），且无明确优先级定义。引擎只读 Rule 的。

### 2.5 渲染配置三级层叠无明确优先级

1. `DistributionRule.render_config` — 规则级
2. `Rule.targets[i].render_config` — 目标级覆盖
3. BotChat 无 render_config

实际执行中 worker 使用 target_meta 中的 render_config，但优先级未文档化。

### 2.6 三层 enabled 开关

| 层级 | 字段 | 引擎是否检查 |
|------|------|:---:|
| DistributionRule.enabled | 规则总开关 | ✅ |
| Rule.targets[i].enabled | 每目标开关 | ✅ |
| BotChat.enabled | 群组全局开关 | ❌ 未检查 |

BotChat.enabled 仅影响前端列表展示和 sync 范围，不阻止分发。

### 2.7 引擎逻辑缺失与风险 (新增分析)

- **跨规则排重 (De-duplication)**: 如果一个内容同时匹配两个指向同一 `BotChat` 的规则，引擎会创建两个重复的任务。
- **NSFW 路由未实现**: 当前 `separate_channel` 策略仅有日志输出，未实际根据 `BotChat.nsfw_chat_id` 切换目标。
- **前置权限校验缺失**: 引擎未检查 `BotChat.can_post` 或 `BotChat.is_accessible`。
- **推送记录追踪弱**: `PushedRecord` 仅记录 `target_id` (字符串)，当 ID 变更或多账户管理时难以通过外键回溯。

## 3. 目标架构

### 3.1 职责分离原则

```
DistributionRule = WHAT（什么内容匹配）
  ↓ 1:N
DistributionTarget = HOW & WHERE（发到哪 + 怎么发）
  ↓ N:1
BotChat = IDENTITY（端点身份 + 运维状态）
```

### 3.2 DistributionRule（保留，微调）

保留字段：
- `name`, `description`
- `match_conditions` (JSON) — 标签/平台/NSFW 等匹配条件，**唯一的过滤逻辑来源**
- `nsfw_policy` — **唯一的 NSFW 策略来源**
- `render_config` — 规则级默认渲染配置
- `priority`, `enabled`
- `approval_required`, `auto_approve_conditions`
- `rate_limit`, `time_window`
- `template_id`

删除字段：
- `targets` (JSON) — 迁移到 DistributionTarget 表后删除

### 3.3 DistributionTarget（新建表）

```sql
CREATE TABLE distribution_targets (
    id INTEGER PRIMARY KEY,
    rule_id INTEGER NOT NULL REFERENCES distribution_rules(id) ON DELETE CASCADE,
    bot_chat_id INTEGER NOT NULL REFERENCES bot_chats(id) ON DELETE CASCADE,
    enabled BOOLEAN DEFAULT TRUE,
    -- 发送选项（平台特定）
    merge_forward BOOLEAN DEFAULT FALSE,       -- QQ 合并转发
    use_author_name BOOLEAN DEFAULT TRUE,       -- 显示原作者名
    summary TEXT DEFAULT '',                    -- 合并转发显示名
    -- 渲染覆盖
    render_config_override JSON,                -- 覆盖规则级 render_config
    created_at DATETIME,
    updated_at DATETIME,
    UNIQUE(rule_id, bot_chat_id)
);
```

**渲染配置优先级（明确）：**
`target.render_config_override` > `rule.render_config` > 系统默认

### 3.4 BotChat（精简为纯身份）

保留字段：
- `chat_id`, `chat_type` — 端点标识
- `title`, `username`, `description` — 显示信息
- `member_count` — 成员数
- `is_admin`, `can_post` — Bot 权限
- `enabled` — **全局开关**（重构后引擎需检查此字段）
- `is_accessible`, `last_sync_at`, `sync_error` — 可达性
- `nsfw_chat_id` — 配对 NSFW 频道指针（路由用，非策略）
- `total_pushed`, `last_pushed_at` — 统计
- `raw_data` — 原始数据
- 时间戳

删除字段：
- `tag_filter` — 死代码，过滤逻辑归 Rule
- `platform_filter` — 死代码，过滤逻辑归 Rule
- `nsfw_policy` — 死代码，策略归 Rule
- `priority` — 冗余，优先级归 Rule
- `linked_rule_ids` — 被 DistributionTarget FK 替代

## 4. 迁移步骤

### Phase 1：后端模型 + 数据迁移

1. **新建 `DistributionTarget` 模型**（`backend/app/models.py`）
2. **新建 Schema**（`backend/app/schemas.py`）：`DistributionTargetCreate/Update/Response`
3. **数据迁移脚本**：遍历所有 Rule 的 `targets` JSON，为每个 target：
   - 查找或创建对应的 BotChat（按 platform + target_id 匹配 chat_id）
   - 创建 DistributionTarget 记录
4. **清理 BotChat**：从模型中删除 `tag_filter`、`platform_filter`、`nsfw_policy`、`priority`、`linked_rule_ids` 五个字段
5. **(增强) PushedRecord 关联**：考虑将 `PushedRecord.target_id` 改为引用 `BotChat.id` 以增强数据追踪。

### Phase 2：后端 API + 引擎

5. **新建 CRUD 路由**（`backend/app/routers/distribution.py` 或新文件）：
   - `GET /api/v1/distribution-rules/{rule_id}/targets` — 获取规则的目标列表
   - `POST /api/v1/distribution-rules/{rule_id}/targets` — 添加目标（传 bot_chat_id）
   - `PATCH /api/v1/distribution-rules/{rule_id}/targets/{target_id}` — 更新目标配置
   - `DELETE /api/v1/distribution-rules/{rule_id}/targets/{target_id}` — 删除目标
6. **更新分发引擎** `engine.py`：
   - `create_distribution_tasks()` 改为查询 `DistributionTarget` JOIN `BotChat`
   - **新增：任务级排重**。确保同一 Content 对同一 BotChat 只产生一条任务（取优先级最高的规则或合并渲染配置）。
   - **新增：前置校验**。显式检查 `BotChat.enabled`, `BotChat.is_accessible` 和 `BotChat.can_post`。
   - **新增：NSFW 路由**。当策略为 `separate_channel` 时，读取关联 `BotChat.nsfw_chat_id` 作为分发目标。
7. **清理 BotChat API**：
   - 删除 `link-rule`/`unlink-rule` 端点
   - BotChat Create/Update schema 移除已删字段
8. **保持 Rule 的 `targets` JSON 字段暂时只读**（向后兼容），后续版本再删除

### Phase 3：前端 UI

9. **Rule 对话框**（`distribution_rule_dialog.dart`）：
   - "分发目标" 部分改为从已有 BotChat 列表中选择（下拉/搜索）
   - 选中后展开该目标的配置（merge_forward / render override 等）
   - 移除手动输入 target_id 的方式
10. **BotChat 对话框**（`bot_chat_dialog.dart`）：
    - 移除标签过滤器、NSFW 策略选择器、优先级、关联规则选择器
    - 仅保留：Chat ID/类型、显示名称、启用开关、NSFW 配对频道
11. **BotChat 卡片**（`bot_chat_card.dart`）：
    - 移除 tag_filter / platform_filter 的显示
    - 可选：显示"被 N 条规则使用"统计
12. **新建 Dart 模型** `DistributionTarget`（freezed）
13. **更新 Provider**：Rule 的 targets 改为通过新 API 获取

## 5. 涉及文件清单

### 后端
| 文件 | 变更类型 |
|------|---------|
| `backend/app/models.py` | 新增 DistributionTarget 模型；BotChat 删除 5 个字段 |
| `backend/app/schemas.py` | 新增 Target schema；清理 BotChat schema；清理 Rule schema 的 targets 字段 |
| `backend/app/distribution/engine.py` | 重写 create_distribution_tasks 使用新表 |
| `backend/app/routers/distribution.py` | 新增 Target CRUD 端点 |
| `backend/app/routers/bot_management.py` | 删除 link-rule/unlink-rule；清理 BotChat CRUD |
| `backend/app/worker/` | 更新 dispatch 逻辑适配新 target_meta 来源 |

### 前端
| 文件 | 变更类型 |
|------|---------|
| `frontend/lib/features/review/models/distribution_rule.dart` | 移除 targets 字段 |
| `frontend/lib/features/review/models/bot_chat.dart` | 移除 tagFilter/platformFilter/nsfwPolicy/priority/linkedRuleIds |
| `frontend/lib/features/review/models/distribution_target.dart` | **新建** |
| `frontend/lib/features/review/providers/distribution_targets_provider.dart` | **新建** |
| `frontend/lib/features/review/widgets/distribution_rule_dialog.dart` | 目标部分改为选择 BotChat |
| `frontend/lib/features/review/widgets/target_editor_dialog.dart` | 适配新模型 |
| `frontend/lib/features/review/widgets/bot_chat_dialog.dart` | 移除过滤/策略 UI |
| `frontend/lib/features/review/widgets/bot_chat_card.dart` | 移除 filter 显示 |

## 6. 验证要点

- [ ] 迁移后所有现有 Rule.targets JSON 数据完整转移到 distribution_targets 表
- [ ] 分发引擎使用新表后，推送行为与迁移前一致（相同内容推送到相同目标）
- [ ] **多规则排重**：同一 Content 匹配多个指向同一 BotChat 的规则时，只产生一个推送任务。
- [ ] BotChat.enabled = false 时，引擎跳过该目标
- [ ] BotChat.is_accessible = false 时，引擎跳过该目标
- [ ] **权限保护**：BotChat.can_post = false 时，引擎跳过多目标。
- [ ] NSFW separate 策略：内容路由到 BotChat.nsfw_chat_id
- [ ] 渲染优先级：target override > rule default > 系统默认
- [ ] 删除 Rule 时级联删除其 distribution_targets
- [ ] 删除 BotChat 时级联删除关联的 distribution_targets
- [ ] 前端 Rule 对话框可正常添加/编辑/删除目标
- [ ] 前端 BotChat 对话框不再展示已删除的字段
- [ ] `flutter analyze` 无错误
- [ ] `pytest tests/` 通过
