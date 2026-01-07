# M5 自动推送功能使用指南

## 功能概述

M5 实现了完整的自动推送系统，包括：

1. **Worker 分发任务处理** - 响应 M4 分发引擎的推送请求
2. **定时轮询推送** - 自动检查待推送内容并批量推送
3. **交互式按钮** - 支持内联键盘操作（标记NSFW/重解析/删除）
4. **用户权限控制** - 白名单/黑名单/管理员机制

## 新增文件

- `app/push_service.py` - 推送服务，封装 Telegram Bot API 调用
- `app/distribution_scheduler.py` - 分发调度器，定时检查并推送
- `tests/test_m5_distribution.py` - 测试脚本

## 配置项

在 `.env` 文件中添加以下配置：

```bash
# Bot 权限控制
TELEGRAM_ADMIN_IDS=123456,789012  # 管理员用户ID列表，逗号分隔
TELEGRAM_WHITELIST_IDS=           # 白名单用户ID（为空则允许所有用户）
TELEGRAM_BLACKLIST_IDS=           # 黑名单用户ID
```

## 使用方式

### 1. 启动后端服务

```bash
# 启动后端（包含 Worker 和分发调度器）
uvicorn app.main:app --reload --port 8000
```

后端启动后会自动：
- 启动 Worker（处理解析和分发任务）
- 启动分发调度器（每60秒检查一次待推送内容）

### 2. 启动 Telegram Bot

```bash
python -m app.bot
```

Bot 启动后支持以下命令：
- `/get` - 随机获取内容
- `/get_tag <标签>` - 按标签获取
- `/get_twitter` - 获取 Twitter 内容
- `/get_bilibili` - 获取 B站内容
- `/list_tags` - 查看所有标签
- `/status` - 系统状态

### 3. 创建分发规则

通过 API 创建分发规则：

```bash
curl -X POST http://localhost:8000/api/v1/distribution-rules \
  -H "Content-Type: application/json" \
  -d '{
    "name": "自动推送技术内容",
    "description": "将tech标签的内容推送到技术频道",
    "match_conditions": {
      "tags": ["tech"],
      "is_nsfw": false
    },
    "targets": [
      {
        "platform": "telegram",
        "target_id": "@my_tech_channel",
        "enabled": true
      }
    ],
    "nsfw_policy": "block",
    "enabled": true
  }'
```

### 4. 审批内容

内容需要先审批才能推送：

```bash
# 批量审批
curl -X POST http://localhost:8000/api/v1/contents/batch-review \
  -H "Content-Type: application/json" \
  -d '{
    "content_ids": [1, 2, 3],
    "review_status": "approved"
  }'
```

### 5. 自动推送流程

1. 分发调度器每60秒检查一次
2. 根据分发规则匹配 `approved` 且未推送的内容
3. 创建分发任务放入队列
4. Worker 取出任务，调用 PushService 发送到 Telegram
5. 记录推送结果到 `pushed_records` 表

## 交互式按钮

发送到频道的消息会附带管理按钮：

- **🔞 标记NSFW** - 将内容标记为敏感内容
- **🔄 重解析** - 触发内容重新解析
- **🗑️ 删除** - 删除内容（仅管理员）

点击按钮后会：
1. 验证管理员权限
2. 调用相应的 API
3. 更新按钮消息显示结果

## 权限控制

### 管理员权限
- 可以使用所有命令
- 可以点击管理按钮（标记NSFW/重解析/删除）

### 白名单模式
- 如果配置了 `TELEGRAM_WHITELIST_IDS`，只有白名单用户可使用Bot
- 管理员自动在白名单中

### 黑名单
- 黑名单用户完全禁止使用Bot

## 频率限制

为防止 Telegram API 限流，系统实现了：
- 20条/分钟的推送限制
- 超过限制后自动暂停推送
- 下一轮调度周期继续处理

## 测试

运行测试脚本：

```bash
./backend/.venv/bin/python backend/tests/test_m5_distribution.py
```

测试会：
1. 检查已批准的内容
2. 检查启用的分发规则
3. 创建一个测试分发任务

## 故障排查

### 推送不工作

1. 检查分发规则是否启用
2. 检查内容是否已审批（`review_status` = approved）
3. 检查是否已推送过（查询 `pushed_records` 表）
4. 查看 Worker 日志

### 按钮点击无响应

1. 检查用户是否是管理员
2. 检查后端 API 是否正常
3. 查看 Bot 日志

### 权限问题

1. 检查 `.env` 配置是否正确
2. 确认用户ID正确（可在日志中查看）
3. 重启 Bot 以加载新配置

## 监控

查看系统状态：

```bash
# 通过 Bot
/status

# 通过 API
curl http://localhost:8000/health
```

## 下一步

- [ ] 实现消息编辑/撤回功能
- [ ] 添加推送成功率统计
- [ ] 支持多个 Telegram 频道/群组
- [ ] 实现 Web 管理界面
