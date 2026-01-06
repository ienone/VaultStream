# API 接口契约（M1）

## 鉴权

- 可选 Token：当配置了 `API_TOKEN` 时，所有写入接口必须鉴权。
- 传递方式（二选一）：
  - Header: `X-API-Token: <token>`
  - Header: `Authorization: Bearer <token>`

未配置 `API_TOKEN` 时（默认为空），为方便本地开发，接口不会校验。

## POST /api/v1/shares

### 作用

提交一个分享入口，后端会：

- 识别平台
- 规范化/净化 URL 得到 `canonical_url`
- 按 `(platform, canonical_url)` 去重
- 为每次提交写入一条 `content_sources`（来源追踪）
- 若为首次入库，则创建 `contents` 并入队解析任务

### Request Body

```json
{
  "url": "https://www.bilibili.com/video/BVxxxxxx",
  "tags": ["技术", "教程"],
  "source": "web|app|bot",
  "note": "可选备注",
  "client_context": {"device": "android", "app_version": "1.0.0"},
  "is_nsfw": false
}
```

- `url`: 必填。当前已支持 B 站 URL，以及 BV/av/cv 直接输入。
- `tags`: 可选，数组。
- `source`: 可选，来源标识。
- `note`: 可选，备注（硬约束：最大 2000 字符）。
- `client_context`: 可选，任意 JSON 对象（后端不解析，只存档；硬约束：JSON 序列化后最大 4096 bytes）。
- `is_nsfw`: 可选，默认 false。

### Response

```json
{
  "id": 1,
  "platform": "bilibili",
  "url": "https://www.bilibili.com/video/BVxxxxxx",
  "status": "unprocessed",
  "created_at": "2026-01-03T00:00:00Z"
}
```

说明：

- 若命中去重（同平台同 canonical_url 已存在），返回已有内容的 `id`，并仍会写入一条 `content_sources`。

- 存档优先行为说明：当同一内容已存在时，后续 `POST /api/v1/shares` 会更新内容的 `tags` 与 `source`（合并 tags），并始终写入 `content_sources` 以便追踪来源。若内容尚未解析成功（`status` 不是 `pulled` 且不是 `processing`），该接口会把内容重新置为 `unprocessed` 并重新入队解析；已解析成功的内容不会重复入队。

## 状态机（最小约束）

- `unprocessed`：创建 contents 后的初始状态（已入队等待解析）。
- `processing`：worker 取到任务后置为 processing。
- `pulled`：解析成功并写入结构化字段后置为 pulled。
- `failed`：解析异常时置为 failed。
  - 后端会落库失败信息（用于后续可视化/人工修复）：`failure_count`、`last_error_type`、`last_error`、`last_error_at`（以及可选的 `last_error_detail`）。
  - 当前最小重试方式：再次调用 `POST /shares` 提交同一内容（命中去重后若状态为 failed，会重新入队解析并把状态置回 unprocessed）。
- `archived`：预留人工归档状态（当前未强制自动流转）。

> 兼容说明：旧版本曾使用 `distributed` 作为状态；当前已改为“分发历史仅记录在 pushed_records”，后续会逐步把历史数据回写为 `pulled`。

### 关于“分发/转发”

VaultStream 以“存档”为主，因此“是否已转发到某个去向”不应作为全局状态机层级；它是内容的一组分发属性（按目标维度记录的历史）。

- 分发历史统一记录在 `pushed_records`：包含 `content_id + target_platform + pushed_at + message_id`。
- 判断“某内容是否已推送到某目标”：查询 `pushed_records` 是否存在对应记录。
- 内容的 `status` 只描述解析/存档流程（unprocessed/processing/pulled/failed/archived），不描述分发情况。

## 查询与管理 (M3)

以下接口为可视化管理端提供支持。

### GET /api/v1/contents

#### 作用
获取收藏内容列表，支持过滤、搜索和分页。

#### Request Parameters
- `q`: 搜索关键字 (全文搜索标题、描述、作者)。
- `platform`: 按平台筛选 (bilibili, twitter 等)。
- `status`: 按解析状态筛选 (unprocessed, pulled, failed, archived)。
- `tag`: 按标签筛选。
- `is_nsfw`: 是否为 NSFW 内容。
- `page`: 页码 (默认 1)。
- `size`: 每页数量 (默认 20)。
- `sort`: 排序方向 (asc/desc，默认 desc)。

#### Response
```json
{
  "items": [...],
  "total": 100,
  "page": 1,
  "size": 20,
  "has_more": true
}
```

### GET /api/v1/contents/{id}

#### 作用
获取单条内容的详细信息（包含媒体资源列表、解析元数据等）。

#### Response
与 `ContentDetail` 模型对应，包含 `title`, `description`, `media_urls`, `raw_metadata` 等字段。

### PATCH /api/v1/contents/{id}

#### 作用
修改内容元数据。

#### Request Body
```json
{
  "tags": ["新标签"],
  "title": "修改后的标题",
  "is_nsfw": true,
  "status": "unprocessed"
}
```

### GET /api/v1/tags

#### 作用
获取库中所有已使用的标签及其计数。

#### Response
```json
{
  "游戏": 42,
  "技术": 15
}
```

### GET /api/v1/dashboard/stats

#### 作用
获取仪表盘全局统计数据。

#### Response
```json
{
  "platform_counts": {"bilibili": 10, "twitter": 5},
  "daily_growth": [{"date": "2026-01-01", "count": 2}, ...],
  "storage_usage_bytes": 104857600
}
```

### GET /api/v1/dashboard/queue

#### 作用
获取队列任务积压及状态统计。

#### Response
```json
{
  "pending": 5,
  "processing": 2,
  "failed": 1,
  "archived": 100,
  "total": 108
}
```

### GET /api/v1/media/{key}

#### 作用
代理本地存储的媒体文件。支持 **HTTP Range** 请求。

#### URL 示例
`/api/v1/media/sha256/xx/yy/zz.webp`
`/api/v1/media/sha256/xx/yy/zz.thumb.webp` (获取缩略图)

