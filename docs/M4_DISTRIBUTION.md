# M4: 分发规则与审批流 API 文档

## 概述

M4 实现了内容的审批流程和分发规则系统，确保只有合规内容能被推送到外部频道/群组，并支持灵活的分发策略配置。

## 核心概念

### 1. 审批流（Review Workflow）

- **审批状态**：
  - `pending`: 待审核（新内容默认状态）
  - `approved`: 已批准（可分发）
  - `rejected`: 已拒绝（不可分发）
  - `auto_approved`: 自动批准（符合自动批准条件）

- **审批策略**：
  - 手动审批：通过 API 逐个或批量审批
  - 自动审批：配置分发规则的 `auto_approve_conditions`，符合条件的内容自动通过

### 2. 分发规则（Distribution Rules）

分发规则定义了哪些内容应该推送到哪些目标平台/频道，支持：

- **匹配条件**（`match_conditions`）：根据标签、平台、NSFW状态筛选内容
- **目标配置**（`targets`）：定义推送目标（Telegram频道、QQ群等）
- **NSFW 策略**（`nsfw_policy`）：
  - `block`: 阻止 NSFW 内容推送（硬失败）
  - `allow`: 允许 NSFW 内容推送
  - `separate_channel`: 推送到独立的 NSFW 频道
- **频率限制**（`rate_limit`、`time_window`）：防止刷屏

### 3. 推送去重

- 基于 `(content_id, target_id)` 唯一约束
- 同一内容推送到同一目标后，不会重复推送
- 支持更新 `message_id`（用于消息更新/撤回场景）

---

## API 端点

### 分享卡片预览

#### GET /api/v1/contents/{content_id}/preview

获取内容的合规分享卡片预览。

**响应示例**：
```json
{
  "id": 123,
  "platform": "bilibili",
  "title": "示例视频标题",
  "summary": "这是一个简短的摘要...",
  "author_name": "UP主名称",
  "cover_url": "https://example.com/cover.jpg",
  "optimized_media": [
    {
      "type": "image",
      "url": "http://localhost:8000/api/v1/media/abc123.webp",
      "size_bytes": 102400
    }
  ],
  "source_url": "https://www.bilibili.com/video/BV1234567890",
  "tags": ["tech", "tutorial"],
  "published_at": "2026-01-06T10:00:00",
  "view_count": 1000,
  "like_count": 50
}
```

**特点**：
- 严格剥离敏感信息（raw_metadata、client_context、内部路径）
- 使用 M3 代理媒体 URL
- 提供优化后的 WebP 图片

---

### 分发规则管理

#### POST /api/v1/distribution-rules

创建分发规则。

**请求示例**：
```json
{
  "name": "Tech内容推送到Telegram",
  "description": "将tech标签的内容推送到技术频道",
  "match_conditions": {
    "tags": ["tech", "programming"],
    "platform": "bilibili",
    "is_nsfw": false
  },
  "targets": [
    {
      "platform": "telegram",
      "target_id": "@my_tech_channel",
      "enabled": true
    }
  ],
  "enabled": true,
  "priority": 10,
  "nsfw_policy": "block",
  "approval_required": false,
  "auto_approve_conditions": {
    "tags": ["safe"],
    "is_nsfw": false
  },
  "rate_limit": 10,
  "time_window": 3600
}
```

**字段说明**：
- `match_conditions`: 匹配条件（tags 为数组，任一匹配即可）
- `targets`: 推送目标列表
- `priority`: 优先级（数字越大越优先）
- `nsfw_policy`: NSFW 策略（block/allow/separate_channel）
- `approval_required`: 是否需要人工审批
- `auto_approve_conditions`: 自动批准条件
- `rate_limit`: 每 `time_window` 秒内最大推送数

#### GET /api/v1/distribution-rules

获取所有分发规则。

**查询参数**：
- `enabled`: 筛选启用状态（true/false）

#### GET /api/v1/distribution-rules/{rule_id}

获取单个分发规则详情。

#### PATCH /api/v1/distribution-rules/{rule_id}

更新分发规则。

**请求示例**：
```json
{
  "enabled": false,
  "priority": 20
}
```

#### DELETE /api/v1/distribution-rules/{rule_id}

删除分发规则。

---

### 审批流程

#### POST /api/v1/contents/{content_id}/review

审批单个内容。

**请求示例**：
```json
{
  "action": "approve",
  "note": "内容质量高，批准推送",
  "reviewed_by": "admin"
}
```

**字段说明**：
- `action`: `approve` 或 `reject`
- `note`: 审批备注（可选）
- `reviewed_by`: 审批人（可选）

#### POST /api/v1/contents/batch-review

批量审批内容。

**请求示例**：
```json
{
  "content_ids": [1, 2, 3, 4, 5],
  "action": "approve",
  "note": "批量通过",
  "reviewed_by": "admin"
}
```

#### GET /api/v1/contents/pending-review

获取待审批内容列表。

**查询参数**：
- `page`: 页码（默认 1）
- `size`: 每页数量（默认 20，最大 100）
- `platform`: 按平台筛选（可选）

**响应示例**：
```json
{
  "items": [
    {
      "id": 123,
      "platform": "bilibili",
      "title": "示例视频",
      "review_status": "pending",
      "created_at": "2026-01-06T10:00:00",
      ...
    }
  ],
  "total": 50,
  "page": 1,
  "size": 20,
  "has_more": true
}
```

---

### 推送记录

#### GET /api/v1/pushed-records

查询推送记录。

**查询参数**：
- `content_id`: 按内容ID筛选（可选）
- `target_id`: 按目标ID筛选（可选）
- `limit`: 返回数量（默认 50，最大 200）

**响应示例**：
```json
[
  {
    "id": 1,
    "content_id": 123,
    "target_platform": "telegram",
    "target_id": "@my_channel",
    "message_id": "1234",
    "push_status": "success",
    "error_message": null,
    "pushed_at": "2026-01-06T11:00:00"
  }
]
```

#### POST /api/v1/bot/mark-pushed

Bot 调用：标记内容已推送。

**请求示例**：
```json
{
  "content_id": 123,
  "target_platform": "telegram",
  "target_id": "@my_channel",
  "message_id": "5678"
}
```

**特点**：
- 如果已存在记录，会更新 `message_id`
- 实现"同一目标推过不再推"逻辑

---

## 使用流程

### 1. 内容入库与自动审批

```
POST /api/v1/shares (url, tags, ...)
  ↓
Worker 解析内容
  ↓
检查自动批准条件
  ↓ (符合条件)
设置 review_status = auto_approved
```

### 2. 人工审批

```
GET /api/v1/contents/pending-review
  ↓
审核人员查看待审批内容
  ↓
POST /api/v1/contents/{id}/review (action=approve/reject)
  ↓
更新 review_status
```

### 3. 分发流程（未来完整实现）

```
内容状态变为 approved
  ↓
DistributionEngine 匹配规则
  ↓
检查 NSFW 策略、去重、频率限制
  ↓
创建分发任务
  ↓
Bot 执行推送
  ↓
POST /api/v1/bot/mark-pushed
```

---

## 安全特性

1. **合规分享卡片**：
   - Preview API 严格剥离敏感信息
   - 禁止泄露 raw_metadata、cookie、内部路径

2. **NSFW 闸门**：
   - 硬失败机制：NSFW 内容不能推送到非 NSFW 频道
   - 可配置独立的 NSFW 频道

3. **推送去重**：
   - 数据库唯一约束保证同一内容不重复推送到同一目标
   - 支持幂等更新

4. **频率限制**：
   - 防止短时间内大量刷屏
   - 基于时间窗口的限流策略

---

## 数据库迁移

已完成：
```sql
migrations/m4_distribution_and_review.sql
```

包含：
- `contents` 表增加审批字段
- `pushed_records` 表增加 target_id、push_status 等字段
- 创建 `distribution_rules` 表
- 自动将已解析内容设置为 auto_approved

---

## 后续计划

1. **Worker 主动分发**：当前仅创建 pending 推送记录，需要实现主动推送逻辑
2. **Web 管理界面**：可视化管理审批流程和分发规则
3. **推送模板**：支持自定义推送消息格式
4. **AI 辅助审批**：集成 AI 摘要和内容审核建议
