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

## 状态机（最小约束）

- `unprocessed`：创建 contents 后的初始状态（已入队等待解析）。
- `processing`：worker 取到任务后置为 processing。
- `pulled`：解析成功并写入结构化字段后置为 pulled。
- `failed`：解析异常时置为 failed（后续可引入重试机制/重新入队/人工修复/手动设置解析内容后重试）。
- `archived`：预留人工归档状态（当前未强制自动流转）。

> 兼容说明：旧版本曾使用 `distributed` 作为状态；当前已改为“分发历史仅记录在 pushed_records”，后续会逐步把历史数据回写为 `pulled`。

### 关于“分发/转发”

VaultStream 以“存档”为主，因此“是否已转发到某个去向”不应作为全局状态机层级；它是内容的一组分发属性（按目标维度记录的历史）。

- 分发历史统一记录在 `pushed_records`：包含 `content_id + target_platform + pushed_at + message_id`。
- 判断“某内容是否已推送到某目标”：查询 `pushed_records` 是否存在对应记录。
- 内容的 `status` 只描述解析/存档流程（unprocessed/processing/pulled/failed/archived），不描述分发情况。
