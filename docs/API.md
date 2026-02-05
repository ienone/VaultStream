# VaultStream API 文档

> 版本: v0.2.0  
> 更新: 2026-02-03  
> 基于优化报告全面改进

## 目录

- [鉴权](#鉴权)
- [内容管理 API](#内容管理-api)
- [批量操作 API](#批量操作-api)
- [实时事件 SSE](#实时事件-sse)
- [队列管理 API](#队列管理-api)
- [分发规则 API](#分发规则-api)
- [Bot 管理 API](#bot-管理-api)
- [系统 API](#系统-api)
- [优化亮点](#优化亮点)
- [迁移指南](#迁移指南)

---

## 鉴权

所有 API 请求需要携带 Token（可选配置）：

**传递方式**（二选一）：
- Header: `X-API-Token: <your-token>`
- Header: `Authorization: Bearer <your-token>`

**配置说明**：
- 未配置 `API_TOKEN` 环境变量时，鉴权跳过（方便本地开发）
- 生产环境建议设置强Token

---

## 内容管理 API

### POST /api/v1/shares

提交分享URL，创建内容收藏项。

**功能**：
- 自动识别平台（Bilibili、Twitter、小红书、微博、知乎等）
- URL规范化与去重
- 异步解析与存档
- 来源追踪

**Request Body**：
```json
{
  "url": "https://www.bilibili.com/video/BV1xx411c7mu",
  "tags": ["技术", "教程"],
  "source": "web",
  "note": "可选备注（最长2000字符）",
  "client_context": {"device": "desktop"},
  "is_nsfw": false,
  "layout_type_override": "gallery"
}
```

**Response**：
```json
{
  "id": 123,
  "platform": "bilibili",
  "url": "https://www.bilibili.com/video/BV1xx411c7mu",
  "status": "unprocessed",
  "created_at": "2026-02-03T10:00:00Z"
}
```

**去重行为**：
- 相同平台 + 相同canonical_url → 返回已有内容
- 失败状态自动重试解析


### GET /api/v1/contents

获取内容列表（支持字段过滤优化）。

**Query Parameters**：
```
page=1                     # 页码（默认1）
size=20                    # 每页数量（默认20，最大100）
platform=bilibili          # 平台筛选（可多选，逗号分隔）
status=pulled              # 状态筛选
review_status=approved     # 审核状态
tag=技术                   # 标签筛选（可多选）
author=作者名              # 作者筛选
start_date=2026-01-01      # 开始日期
end_date=2026-02-03        # 结束日期
q=关键词                   # 全文搜索
is_nsfw=false              # NSFW筛选
exclude_fields=raw_metadata,extra_stats  # 🆕 排除字段（优化传输）
```

**字段过滤优化**：
- `exclude_fields`: 默认排除 `raw_metadata,extra_stats`（减少70-85%数据量）
- 设置 `exclude_fields=` (空) 可获取全量数据
- 列表页建议使用默认值，详情页请求全量

**Response**：
```json
{
  "items": [
    {
      "id": 123,
      "platform": "bilibili",
      "url": "https://...",
      "status": "pulled",
      "title": "视频标题",
      "cover_url": "https://...",
      "author_name": "作者",
      "tags": ["技术"],
      "is_nsfw": false,
      "created_at": "2026-02-03T10:00:00Z",
      "published_at": "2026-02-01T08:00:00Z"
    }
  ],
  "total": 100,
  "page": 1,
  "size": 20,
  "has_more": true
}
```


### GET /api/v1/contents/{id}

获取内容详情（完整字段）。

**Response**：返回完整 `ContentDetail` 包含所有字段和元数据


### PATCH /api/v1/contents/{id}

更新内容元数据。

**Request Body**：
```json
{
  "tags": ["新标签"],
  "title": "修改标题",
  "description": "新描述",
  "author_name": "作者名",
  "cover_url": "https://...",
  "is_nsfw": true,
  "status": "pulled",
  "review_status": "approved",
  "review_note": "审核通过",
  "reviewed_by": "admin",
  "layout_type_override": "article"
}
```

**实时事件**: 触发 `content_updated` SSE事件


### DELETE /api/v1/contents/{id}

删除内容及关联数据（ContentSource、PushedRecord）。

**实时事件**: 触发 `content_deleted` SSE事件


### POST /api/v1/contents/{id}/re-parse

强制重新解析内容（后台异步任务）。

**实时事件**: 触发 `content_re_parsed` SSE事件

---

## 批量操作 API

### POST /api/v1/contents/batch-update

批量更新内容（性能优化：单次请求，6倍提速）。

**Request Body**：
```json
{
  "content_ids": [1, 2, 3],
  "updates": {
    "tags": ["批量标签"],
    "is_nsfw": false,
    "review_status": "approved"
  }
}
```

**限制**：最多100个ID

**Response**：
```json
{
  "success_count": 3,
  "failed_count": 0,
  "success_ids": [1, 2, 3],
  "failed_ids": [],
  "errors": {}
}
```


### POST /api/v1/contents/batch-delete

批量删除内容（最多100个）。


### POST /api/v1/contents/batch-re-parse

批量重新解析（最多20个，避免过载）。

---

## 实时事件 SSE

### GET /api/v1/events/subscribe

订阅服务端推送事件（Server-Sent Events）。

**使用方式**：
```javascript
const eventSource = new EventSource('/api/v1/events/subscribe');

eventSource.addEventListener('content_updated', (e) => {
  const data = JSON.parse(e.data);
  console.log('内容更新:', data);
});
```

**支持事件**：

- `content_updated`: 内容更新
- `content_deleted`: 内容删除
- `content_re_parsed`: 重新解析
- `queue_item_reordered`: 队列重排序
- `bot_status_changed`: Bot状态变化


### GET /api/v1/events/health

事件系统健康检查。

---

## 队列管理 API

### GET /api/v1/queue/items

获取分发队列内容。

**Query Parameters**：
```
rule_id=1        # 按规则筛选
status=will_push # 状态：will_push/filtered/pending_review/pushed
limit=50         # 返回数量
```


### POST /api/v1/queue/items/{id}/move

移动队列项到指定状态（will_push/filtered/pending_review）。


### POST /api/v1/queue/items/{id}/reorder

重新排序队列项（优化：无跳变）。

**Request Body**：
```json
{
  "index": 3
}
```

**优化机制**：
- 调整 `queue_priority` 控制顺序
- 前端本地立即更新UI
- 延迟软刷新（避免跳变）
- SSE事件通知其他客户端


### POST /api/v1/queue/batch-push-now

批量立即推送。


### POST /api/v1/queue/batch-reschedule

批量重新排期。

---

## 分发规则 API

### GET /api/v1/distribution-rules

获取分发规则列表。


### POST /api/v1/distribution-rules

创建分发规则（支持标签、平台、NSFW策略等条件）。


### PATCH /api/v1/distribution-rules/{id}

更新分发规则。


### DELETE /api/v1/distribution-rules/{id}

删除分发规则。

---

## Bot 管理 API

### GET /api/v1/bot/chats

获取Bot群组列表。


### POST /api/v1/bot/chats

添加Bot群组。


### GET /api/v1/bot/status

获取Bot运行状态（是否运行、连接群组数、今日推送数等）。


### POST /api/v1/bot/sync-chats

同步Bot群组信息。

---

## 系统 API

### GET /api/v1/tags

获取所有标签及统计。


### GET /api/v1/dashboard/stats

仪表盘统计（平台分布、每日增长、存储使用）。


### GET /health

健康检查（数据库、Redis状态）。

---

## 状态码

- `200 OK`: 成功
- `201 Created`: 创建成功
- `400 Bad Request`: 请求参数错误
- `401 Unauthorized`: 未授权
- `404 Not Found`: 资源不存在
- `500 Internal Server Error`: 服务器错误

---

## 优化亮点

### 1. 字段选择优化
- `exclude_fields` 参数减少 **70-85%** 数据传输
- 列表/详情分离策略

### 2. 批量操作
- 单次请求处理多项
- 性能提升 **6倍**

### 3. 实时推送
- SSE事件驱动
- 减少 **90%** 手动刷新

### 4. 队列优化
- 无跳变重排序
- 优先级精确控制

---

## 迁移指南

### 从旧版API迁移

**批量操作**：
```dart
// ❌ 旧方式（循环调用）
for (var id in ids) {
  await api.updateContent(id, tags: tags);
}

// ✅ 新方式（批量API）
await api.batchUpdateTags(ids, tags);
```

**列表查询**：
```dart
// ✅ 默认排除大字段
await api.getContents(page: 1);

// 获取完整数据
await api.getContents(page: 1, excludeFields: '');
```

**实时更新**：
```dart
// ❌ 旧方式（手动刷新）
onPressed: () => ref.invalidate(contentsProvider);

// ✅ 新方式（SSE自动刷新）
// 订阅事件，自动更新
```

---

*文档版本: v0.2.0*  
*最后更新: 2026-02-03*

