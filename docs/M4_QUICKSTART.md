# M4 快速启动指南

## 前置条件

- M0-M3 已完成（数据库、存储、解析流程）
- 已执行 M4 数据库迁移

## 1. 执行数据库迁移（如果还没执行）

```bash
cd [PROJECT_ROOT]
sqlite3 data/vaultstream.db < migrations/m4_distribution_and_review.sql
```

## 2. 启动后端服务

```bash
# 使用项目文件夹内的Python
cd [PROJECT_ROOT]
python3 -m app.main
```

或使用启动脚本：
```bash
./start.sh
```

## 3. 创建第一个分发规则

### 使用 curl 创建规则

```bash
curl -X POST http://localhost:8000/api/v1/distribution-rules \
  -H "Content-Type: application/json" \
  -H "X-API-Token: dev-token-12345" \
  -d '{
    "name": "技术内容推送到Telegram",
    "description": "将tech标签的内容推送到技术频道",
    "match_conditions": {
      "tags": ["tech", "programming"],
      "is_nsfw": false
    },
    "targets": [
      {
        "platform": "telegram",
        "target_id": "@your_channel_name",
        "enabled": true
      }
    ],
    "enabled": true,
    "priority": 10,
    "nsfw_policy": "block",
    "approval_required": false,
    "auto_approve_conditions": {
      "is_nsfw": false
    }
  }'
```

### 使用 Python 脚本

```python
import requests

response = requests.post(
    "http://localhost:8000/api/v1/distribution-rules",
    headers={"X-API-Token": "dev-token-12345"},
    json={
        "name": "技术内容推送",
        "match_conditions": {"tags": ["tech"]},
        "targets": [{"platform": "telegram", "target_id": "@channel"}],
        "enabled": True,
        "nsfw_policy": "block"
    }
)
print(response.json())
```

## 4. 测试分享卡片预览

```bash
# 假设已有内容 ID=1
curl http://localhost:8000/api/v1/contents/1/preview \
  -H "X-API-Token: dev-token-12345"
```

## 5. 审批待审内容

### 查看待审批内容

```bash
curl http://localhost:8000/api/v1/contents/pending-review \
  -H "X-API-Token: dev-token-12345"
```

### 批准单个内容

```bash
curl -X POST http://localhost:8000/api/v1/contents/1/review \
  -H "Content-Type: application/json" \
  -H "X-API-Token: dev-token-12345" \
  -d '{
    "action": "approve",
    "note": "内容质量好",
    "reviewed_by": "admin"
  }'
```

### 批量批准

```bash
curl -X POST http://localhost:8000/api/v1/contents/batch-review \
  -H "Content-Type: application/json" \
  -H "X-API-Token: dev-token-12345" \
  -d '{
    "content_ids": [1, 2, 3],
    "action": "approve",
    "reviewed_by": "admin"
  }'
```

## 6. 查询推送记录

```bash
# 查看所有推送记录
curl http://localhost:8000/api/v1/pushed-records \
  -H "X-API-Token: dev-token-12345"

# 按内容ID筛选
curl "http://localhost:8000/api/v1/pushed-records?content_id=1" \
  -H "X-API-Token: dev-token-12345"

# 按目标ID筛选
curl "http://localhost:8000/api/v1/pushed-records?target_id=@channel" \
  -H "X-API-Token: dev-token-12345"
```

## 7. Bot 标记推送

当 Telegram Bot 成功推送后，应调用此API：

```bash
curl -X POST http://localhost:8000/api/v1/bot/mark-pushed \
  -H "Content-Type: application/json" \
  -d '{
    "content_id": 1,
    "target_platform": "telegram",
    "target_id": "@my_channel",
    "message_id": "12345"
  }'
```

## 8. 运行测试脚本

```bash
cd [PROJECT_ROOT]
python3 tests/test_m4_features.py
```

## 常见使用场景

### 场景 1：自动审批+自动分发

1. 创建规则，设置 `approval_required: false` 和 `auto_approve_conditions`
2. 新内容解析完成后自动批准
3. DistributionEngine 自动匹配规则并创建分发任务

### 场景 2：人工审批+手动分发

1. 创建规则，设置 `approval_required: true`
2. 定期查询 `/contents/pending-review`
3. 人工审批后，Bot 拉取并推送

### 场景 3：NSFW 内容分流

1. 创建两条规则：
   - 规则1：普通内容推送到主频道（`nsfw_policy: "block"`）
   - 规则2：NSFW 内容推送到 NSFW 频道（`nsfw_policy: "allow"`）
2. NSFW 内容会被自动路由到对应频道

## 配置说明

### 分发规则字段

- `match_conditions`: 匹配条件
  ```json
  {
    "tags": ["tech"],       // 包含任一标签
    "platform": "bilibili", // 平台匹配
    "is_nsfw": false        // NSFW 状态
  }
  ```

- `targets`: 目标配置
  ```json
  [
    {
      "platform": "telegram",
      "target_id": "@channel_name",
      "enabled": true
    }
  ]
  ```

- `nsfw_policy`: 
  - `"block"`: 阻止 NSFW 内容（硬失败）
  - `"allow"`: 允许 NSFW 内容
  - `"separate_channel"`: 分流到独立频道

- `rate_limit` 和 `time_window`:
  - `rate_limit: 10, time_window: 3600` = 每小时最多推送 10 条

### 自动审批条件

```json
{
  "auto_approve_conditions": {
    "is_nsfw": false,
    "tags": ["safe"]
  }
}
```

满足所有条件的内容会自动批准。

## 故障排查

### 1. 内容未自动批准

- 检查是否有规则配置了 `auto_approve_conditions`
- 确认内容符合自动批准条件
- 查看后端日志确认自动审批检查是否执行

### 2. 推送记录重复

- 检查是否正确使用 `target_id`（不是 `target_platform`）
- 确认唯一约束已正确创建：`(content_id, target_id)`

### 3. NSFW 内容推送失败

- 检查目标规则的 `nsfw_policy` 设置
- 确认内容的 `is_nsfw` 字段正确

## 下一步

- 参考 [M4 API 文档](M4_DISTRIBUTION.md) 了解详细API
- 参考 [M4 实施总结](M4_IMPLEMENTATION_SUMMARY.md) 了解架构设计
- 开始实施 M5：Bot 与分发引擎集成
