# 分发系统架构优化与完整流程设计

> 文档创建时间: 2026-02-13
> 
> 本文档阐述 VaultStream 分发引擎的四层架构设计、完整使用流程以及优化方案。

---

## 目录

1. [Bot 配置功能需求](#一bot-配置功能需求)
2. [优化后的四层架构设计](#二优化后的四层架构设计)
3. [完整使用流程](#三完整使用流程)
4. [关键优化点](#四关键优化点)
5. [实施顺序建议](#五实施顺序建议)

---

## 一、Bot 配置功能需求

### 当前状态

- **Telegram Bot**: Token 通过环境变量 `TELEGRAM_BOT_TOKEN` 配置，硬编码在 `app/push/telegram.py`
- **Napcat (QQ)**: 配置在 `app/push/napcat.py`，需要 `NAPCAT_HTTP_URL` 和 `NAPCAT_WS_URL`
- **BotRuntime 表**: 只存储运行时状态（心跳、版本），不存储配置信息

### 改进方向

#### 1. 新建 `BotConfig` 模型

存储多 Bot 账号的配置信息：

```python
class BotConfig(Base):
    """Bot 配置表（支持多 Bot 管理）"""
    __tablename__ = "bot_configs"
    
    id = Column(Integer, primary_key=True)
    platform = Column(String(20), nullable=False)  # telegram | qq
    name = Column(String(100), nullable=False)  # 用户自定义名称
    
    # Telegram 专用
    bot_token = Column(String(200))
    
    # QQ/Napcat 专用
    napcat_http_url = Column(String(200))
    napcat_ws_url = Column(String(200))
    
    # 状态
    enabled = Column(Boolean, default=True)
    is_primary = Column(Boolean, default=False)  # 是否为主 Bot
    
    # 元数据
    bot_id = Column(String(50))  # TG: bot_id, QQ: qq_number
    bot_username = Column(String(100))
    
    # 关系
    chats = relationship("BotChat", back_populates="bot_config")
    
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
```

#### 2. 后端 API 端点

- `POST /api/v1/bot-config` - 添加 Bot 配置
- `GET /api/v1/bot-config` - 列出所有 Bot
- `PATCH /api/v1/bot-config/{id}` - 更新 Bot 配置
- `DELETE /api/v1/bot-config/{id}` - 删除 Bot
- `GET /api/v1/bot-config/{id}/qr-code` - 获取 Napcat 登录二维码（WebSocket 流式传输）
- `POST /api/v1/bot-config/{id}/activate` - 激活/切换主 Bot
- `POST /api/v1/bot-config/{id}/sync-chats` - 同步该 Bot 的群组列表

#### 3. 前端功能

- **Bot 管理页面** (`BotManagementPage`)
  - 列出所有已配置的 Bot
  - 显示在线状态、关联群组数
  - 支持快捷切换主 Bot
- **添加 Bot 向导** (`AddBotWizard`)
  - 步骤 1: 选择平台（Telegram/QQ）
  - 步骤 2: 输入凭证
    - Telegram: Bot Token + 实时验证
    - QQ: Napcat URL + 显示登录二维码
  - 步骤 3: 自动同步群组列表

---

## 二、优化后的四层架构设计

```
┌─────────────────────────────────────────────────────────────┐
│  第 1 层：Bot 本体 (BotConfig)                                │
│  ────────────────────────────────────────────────────────    │
│  职责：管理 Bot 账号的身份凭证和连接信息                          │
│  字段：                                                        │
│    - platform: telegram | qq                                 │
│    - bot_token (TG) | napcat_api_url (QQ)                   │
│    - enabled, is_primary                                     │
│  关系：一对多 → BotChat                                        │
└─────────────────────────────────────────────────────────────┘
                           ↓ has_many
┌─────────────────────────────────────────────────────────────┐
│  第 2 层：Bot 加入的会话 (BotChat)                             │
│  ────────────────────────────────────────────────────────    │
│  职责：存储 Bot 已加入的群组/频道/私聊的身份信息                   │
│  字段：                                                        │
│    - bot_config_id (外键 → BotConfig)                        │
│    - chat_id, chat_type, title, username                    │
│    - is_accessible, last_sync_at                            │
│  关系：多对多 ↔ DistributionRule (通过中间表)                  │
└─────────────────────────────────────────────────────────────┘
                           ↑                    ↑
                    belongs_to          many_to_many (via)
                           │                    │
                ┌──────────┘                    └──────────┐
                │                                          │
┌───────────────────────────┐       ┌──────────────────────────────────┐
│  第 3 层：分发规则         │       │  第 4 层：关联配置 (中间表)        │
│  (DistributionRule)       │◄──────│  (BotChatRuleConfig)             │
│  ─────────────────────    │       │  原名 DistributionTarget          │
│  职责：定义内容过滤条件     │       │  ─────────────────────────────   │
│  与推送格式               │       │  职责：一个群组应用一个规则的配置   │
│  字段：                   │       │  字段：                           │
│    - match_conditions    │       │    - rule_id (FK)                │
│    - render_config       │       │    - bot_chat_id (FK)            │
│    - priority, enabled   │       │    - enabled                     │
│    - nsfw_policy         │       │    - render_config_override      │
│    - approval_required   │       │    - merge_forward (QQ专用)      │
└───────────────────────────┘       └──────────────────────────────────┘
```

### 核心关系说明

1. **1:N** - `BotConfig` → `BotChat`
   - 一个 Bot 账号可以加入多个群组/频道
   - 示例：@MyNewsBot 加入了 10 个 Telegram 频道

2. **M:N** - `BotChat` ↔ `DistributionRule`
   - 通过 `BotChatRuleConfig` (原 `DistributionTarget`) 关联
   - 示例：
     - "科技新闻"规则 → 推送到 频道A、频道B、群组C
     - 频道A ← 接收 "科技新闻"、"AI动态"、"开源项目" 三个规则的内容

3. **配置继承与覆盖**
   - Rule 定义全局的 `render_config`（默认渲染格式）
   - `BotChatRuleConfig` 可针对特定群组覆盖：
     ```json
     // 规则全局配置
     Rule.render_config = {
       "layout": "card",
       "show_author": true,
       "show_tags": true
     }
     
     // 针对频道A覆盖（简洁模式）
     BotChatRuleConfig(rule_id=1, bot_chat_id=5).render_config_override = {
       "layout": "minimal",
       "show_tags": false
     }
     ```

---

## 三、完整使用流程

### 阶段 1: 初始化 Bot（一次性配置）

```
┌─ 用户操作 ─────────────────────┐  ┌─ 系统响应 ─────────────────┐
│                                │  │                            │
│ 1. 打开"设置" → "Bot 管理"      │  │                            │
│                                │  │                            │
│ 2. 点击"添加 Bot"               │  │ → 显示向导                  │
│    - 选择平台 (Telegram/QQ)    │  │                            │
│    - [TG] 输入 Bot Token       │  │ → 验证 Token 有效性         │
│    - [QQ] 输入 Napcat API 地址 │  │ → 轮询获取登录二维码         │
│                                │  │   显示在弹窗中扫码           │
│                                │  │                            │
│ 3. 确认添加                     │  │ → POST /bot-config         │
│                                │  │ → 自动触发"同步群组"         │
└────────────────────────────────┘  └────────────────────────────┘
                                           ↓
                                    ┌──────────────────┐
                                    │ 系统自动操作：     │
                                    │ - 调用 TG getMe  │
                                    │ - 调用 getChats  │
                                    │ - 创建 BotChat   │
                                    └──────────────────┘
```

**💡 优化点 1: 自动同步 + 实时进度**
- **当前痛点**: 需要手动点击"同步群组"按钮
- **优化方案**: 添加 Bot 后自动后台同步，WebSocket 实时推送进度
- **实现**: `POST /bot-config` 返回后立即触发异步任务

---

### 阶段 2: 创建分发规则

```
┌─ 用户操作 ─────────────────────────────────────┐
│                                                │
│ 1. 打开"审批与分发" → "内容队列"标签            │
│                                                │
│ 2. 左侧规则列表 → 点击"新建规则"                │
│                                                │
│ 3. 填写规则配置：                               │
│    ────────────────────────────────           │
│    基础信息：                                   │
│      [输入框] 规则名称: "科技新闻"              │
│      [文本域] 描述: "AI/编程相关内容"           │
│                                                │
│    标签匹配：                                   │
│      [标签输入] 包含: AI, 编程, LLM            │
│      [下拉框] 匹配模式: 包含任一 ▼             │
│      [标签输入] 排除: 广告, 营销               │
│                                                │
│    分发策略：                                   │
│      [分段按钮] NSFW: ⚪阻止 ⚪允许 ⚪分离      │
│      [数字框] 优先级: 5                        │
│      [开关] 需要人工审批: OFF                   │
│                                                │
│    🆕 推送目标（新增功能）：                     │
│      ┌─────────────────────────────────┐     │
│      │ ☑ @TechNewsChannel (Telegram)   │     │
│      │   └─ 自定义配置: 简洁模式         │     │
│      │ ☑ AI学习群 (QQ: 123456789)      │     │
│      │   └─ 自定义配置: 合并转发         │     │
│      │ ☐ 私人频道 (Telegram)           │     │
│      │                                 │     │
│      │ [📋 全选] [🔄 刷新列表]          │     │
│      └─────────────────────────────────┘     │
│                                                │
│    渲染配置（可选）：                            │
│      [下拉框] 预设模板: 简洁风格 ▼             │
│      [切换] 高级选项...                        │
│                                                │
│ 4. [创建规则] 按钮                              │
└────────────────────────────────────────────────┘
                    ↓
       POST /api/v1/distribution-rules
       {
         "name": "科技新闻",
         "match_conditions": {
           "tags": ["AI", "编程", "LLM"],
           "tags_match_mode": "any",
           "tags_exclude": ["广告", "营销"]
         },
         "nsfw_policy": "block",
         "priority": 5,
         "approval_required": false,
         "render_config": {...},
         "targets": [  // 🆕 批量创建关联
           {
             "bot_chat_id": 1,
             "enabled": true,
             "render_config_override": {"layout": "minimal"}
           },
           {
             "bot_chat_id": 3,
             "enabled": true,
             "merge_forward": true
           }
         ]
       }
```

**💡 优化点 2: 一键关联目标**
- **当前痛点**: 规则和目标需分两步配置
- **优化方案**: 在创建规则时直接勾选目标群组（如上设计）
- **技术实现**: 
  - 前端: `DistributionRuleDialog` 中嵌入 `BotChatSelector` 组件
  - 后端: `POST /distribution-rules` 支持嵌套 `targets` 数组

---

### 阶段 3: 添加内容到队列

#### 方式 A: 手动添加

```
┌─ 用户操作 ────────────────────────────────────┐
│                                              │
│ 1. 打开"收藏库"页面                           │
│                                              │
│ 2. 找到想分发的内容卡片                       │
│                                              │
│ 3. 点击卡片右上角 [⋮] → "加入分发队列"        │
│                                              │
│ 4. 弹窗显示匹配结果：                         │
│    ┌────────────────────────────────┐       │
│    │ "该内容匹配以下规则："          │       │
│    │                                │       │
│    │ ✓ 科技新闻 (优先级: 5)         │       │
│    │   → 推送到 2 个目标             │       │
│    │                                │       │
│    │ ✓ AI动态 (需要审批)            │       │
│    │   → 推送到 3 个目标             │       │
│    │                                │       │
│    │ [立即加入队列] [取消]           │       │
│    └────────────────────────────────┘       │
└──────────────────────────────────────────────┘
```

#### 方式 B: 自动匹配（后台）

```
系统定时任务 (每分钟):
  1. 查询 status=PULLED 且未入队的内容
  2. 遍历所有 enabled=true 的规则
  3. 对每个内容执行匹配:
     - 检查平台
     - 检查标签（包含/排除/匹配模式）
     - 检查 NSFW 状态
  4. 匹配成功 → 创建 ContentQueue 记录
  5. 设置 scheduled_at (根据优先级和频率限制排期)
```

**💡 优化点 3: 事件驱动替代定时任务**
- **当前痛点**: 依赖定时任务，延迟高（最长 1 分钟）
- **优化方案**: Content 创建后立即触发匹配
- **技术实现**:
  ```python
  # 在 Content 创建后的钩子
  @event.listens_for(Content, 'after_insert')
  def on_content_created(mapper, connection, target):
      if target.status == ContentStatus.PULLED:
          background_tasks.add_task(
              DistributionEngine.match_and_queue, 
              content_id=target.id
          )
  ```

---

### 阶段 4: 审批流程（可选）

```
如果规则启用了 approval_required:

┌─ 用户操作 ────────────────────────────────┐
│                                          │
│ 1. 打开"审批与分发" → 顶部状态筛选器        │
│    点击 [待审批 (3)]                      │
│                                          │
│ 2. 查看内容卡片：                         │
│    ┌──────────────────────────────┐     │
│    │ [封面缩略图]                  │     │
│    │                               │     │
│    │ 标题: "GPT-5 发布会回顾"       │     │
│    │ 标签: AI, GPT, 科技           │     │
│    │ 来源: Bilibili                │     │
│    │                               │     │
│    │ 匹配规则:                      │     │
│    │   • 科技新闻 → 2个目标         │     │
│    │   • AI动态 → 3个目标           │     │
│    │                               │     │
│    │ [✓ 批准] [✗ 拒绝]            │     │
│    └──────────────────────────────┘     │
│                                          │
│ 3. 点击 [批准]                           │
│    → 调用 PATCH /queue/{id}              │
│    → status: pending_review → will_push │
│    → 进入排期队列                         │
└──────────────────────────────────────────┘
```

---

### 阶段 5: 自动分发执行

```
┌─ 系统后台任务 (DistributionScheduler) ────────┐
│                                              │
│ 定时触发: 每 30 秒                            │
│                                              │
│ 执行流程:                                    │
│                                              │
│ 1. 查询待推送内容:                            │
│    SELECT * FROM content_queue               │
│    WHERE status='will_push'                 │
│      AND scheduled_at <= NOW()              │
│    ORDER BY priority DESC, scheduled_at     │
│    LIMIT 10                                 │
│                                              │
│ 2. 对每个内容执行推送:                        │
│    ┌─────────────────────────────────────┐ │
│    │ a) 查找匹配的规则列表                 │ │
│    │                                     │ │
│    │ b) 对每个规则:                       │ │
│    │    - 查询关联的目标群组               │ │
│    │      (via BotChatRuleConfig)        │ │
│    │    - 过滤 enabled=true 的目标        │ │
│    │                                     │ │
│    │ c) 检查频率限制:                     │ │
│    │    - 查询 time_window 内推送次数     │ │
│    │    - 如达到 rate_limit 则跳过        │ │
│    │                                     │ │
│    │ d) 应用 NSFW 策略:                   │ │
│    │    - block: 跳过 NSFW 内容          │ │
│    │    - separate_channel: 路由到备用频道│ │
│    │    - allow: 正常推送                 │ │
│    │                                     │ │
│    │ e) 渲染内容:                         │ │
│    │    base = rule.render_config        │ │
│    │    override = target.render_config  │ │
│    │    final = {**base, **override}     │ │
│    │    message = render(content, final) │ │
│    │                                     │ │
│    │ f) 调用推送服务:                     │ │
│    │    if platform == 'telegram':       │ │
│    │        TelegramPushService.push()   │ │
│    │    elif platform == 'qq':           │ │
│    │        NapcatPushService.push()     │ │
│    │                                     │ │
│    │ g) 记录推送结果:                     │ │
│    │    成功 → 创建 PushedRecord          │ │
│    │    失败 → 标记为 failed + 重试队列   │ │
│    └─────────────────────────────────────┘ │
│                                              │
│ 3. 更新内容队列状态:                          │
│    - 全部成功 → status = 'pushed'            │
│    - 部分失败 → status = 'partial_failed'    │
│    - 全部失败 → status = 'failed'            │
└──────────────────────────────────────────────┘
```

**💡 优化点 4: 预渲染缓存**
- **当前痛点**: 每次推送都重新渲染，延迟高
- **优化方案**: 入队时预渲染并缓存
- **技术实现**:
  ```python
  # ContentQueue 新增字段
  rendered_payloads = Column(JSON)  
  # 格式: {"rule_1_target_5": {...}, "rule_1_target_6": {...}}
  
  # 入队时预渲染
  for rule in matched_rules:
      for target in rule.distribution_targets:
          key = f"rule_{rule.id}_target_{target.id}"
          payload = render_content(content, rule, target)
          rendered_payloads[key] = payload
  ```

---

### 阶段 6: 监控与调整

```
┌─ 用户操作 ────────────────────────────────────┐
│                                              │
│ 1. 打开"审批与分发" → "推送历史"标签          │
│                                              │
│ 2. 查看推送记录：                             │
│    ┌────────────────────────────────┐       │
│    │ [✓] GPT-5 发布会               │       │
│    │    • @TechNewsChannel (TG)     │       │
│    │      12:30 成功                 │       │
│    │    • AI学习群 (QQ: 123456)     │       │
│    │      12:30 成功                 │       │
│    ├────────────────────────────────┤       │
│    │ [✗] Claude 3.5 评测            │       │
│    │    • 私人频道 (TG)              │       │
│    │      12:31 失败: 无权限         │       │
│    │      [🔄 重试]                  │       │
│    └────────────────────────────────┘       │
│                                              │
│ 3. 打开"目标管理"页面：                        │
│    ┌────────────────────────────────┐       │
│    │ [Telegram] @TechNewsChannel    │       │
│    │ 应用规则: 科技新闻, AI动态       │       │
│    │ 总推送: 1,234 次                │       │
│    │ 最后推送: 2分钟前                │       │
│    │                                │       │
│    │ [⚙️ 配置规则] [📊 查看统计]     │       │
│    └────────────────────────────────┘       │
│                                              │
│ 4. 点击"配置规则"弹窗：                        │
│    ┌────────────────────────────────┐       │
│    │ 为 @TechNewsChannel 选择规则:   │       │
│    │                                │       │
│    │ ☑ 科技新闻                      │       │
│    │   └─ [⚙️] 自定义渲染配置        │       │
│    │ ☑ AI动态                        │       │
│    │ ☐ 开源项目                      │       │
│    │ ☐ 产品推荐 (已禁用)             │       │
│    │                                │       │
│    │ [保存] [取消]                   │       │
│    └────────────────────────────────┘       │
└──────────────────────────────────────────────┘
```

---

## 四、关键优化点

### 🎯 高优先级优化

#### 1. 规则创建时一键关联目标
- **当前问题**: 需要先创建规则，再单独配置目标（两步操作）
- **优化方案**: 在 `DistributionRuleDialog` 中内嵌群组选择器
- **技术细节**:
  - 后端: `POST /distribution-rules` 支持嵌套 `targets` 数组
  - 前端: 使用 `CheckboxListTile` 展示所有可用群组
  - 支持批量创建 `BotChatRuleConfig` 记录

#### 2. Bot 配置可视化
- **当前问题**: 需要修改环境变量 + 重启服务
- **优化方案**: 新建 `BotConfigPage` 支持多 Bot 管理
- **功能清单**:
  - ✅ 在线添加/删除 Bot
  - ✅ Telegram: Token 验证
  - ✅ QQ: Napcat 二维码登录
  - ✅ 切换主 Bot
  - ✅ 查看每个 Bot 的群组数和推送统计

#### 3. 事件驱动的队列匹配
- **当前问题**: 依赖定时任务，延迟 0-60 秒
- **优化方案**: Content 创建后立即触发匹配
- **技术实现**:
  ```python
  # SQLAlchemy 钩子
  @event.listens_for(Content, 'after_insert')
  async def on_content_created(mapper, connection, target):
      if target.status == ContentStatus.PULLED:
          await DistributionEngine.match_and_queue(target.id)
  ```

### 💡 中优先级优化

#### 4. 群组视角的规则管理
- **功能**: 在 `BotChatCard` 中显示"应用的规则"标签
- **交互**: 点击进入详情，勾选/取消勾选规则
- **示例**:
  ```
  @TechNewsChannel
  应用规则: 科技新闻, AI动态 (+2)
  [⚙️ 配置规则]
  ```

#### 5. 预渲染缓存
- **优化点**: 避免重复渲染相同内容
- **实现**:
  - `ContentQueue` 新增 `rendered_payloads` JSON 字段
  - 入队时预渲染所有变体（不同规则+目标组合）
  - 推送时直接使用缓存结果

#### 6. WebSocket 实时更新
- **应用场景**:
  - 同步群组时推送进度（"已同步 5/10 个群组..."）
  - 推送成功/失败实时通知前端
  - 队列状态变化实时刷新
- **技术选型**: FastAPI WebSocket + Riverpod StreamProvider

### 🔧 低优先级优化

#### 7. 智能排期算法
- **当前**: 简单的时间窗口 + 计数器
- **改进**: 
  - 考虑目标群组的活跃时段
  - 避免同一时间推送过多内容
  - 支持自定义推送时间段（例如：工作日 9:00-18:00）

#### 8. A/B 测试支持
- **功能**: 同一内容使用不同渲染配置推送到不同群组
- **用途**: 测试哪种格式的点击率/互动率更高

---

## 五、实施顺序建议

### 第一阶段：核心流程打通（1-2 周）

```
✅ 1. 在规则弹窗中添加目标选择
   - 修改 DistributionRuleDialog.dart
   - 添加 BotChatSelector 组件
   - 后端支持嵌套 targets 创建

✅ 2. 激活 TargetsManagementPage
   - 注册到 app_router.dart
   - 在 ReviewPage 中添加入口（新 Tab 或侧边栏）

✅ 3. 完善 BotChat ↔ Rule 的双向管理
   - 在 BotChatCard 中显示应用的规则
   - 实现"为群组选择规则"弹窗
   - 支持快捷启用/禁用规则
```

### 第二阶段：Bot 配置功能（1 周）

```
🔧 4. 新建 BotConfig 模型和 API
   - 创建数据库迁移
   - 实现 CRUD 端点
   - 实现 QR Code 生成 API

🔧 5. 前端 Bot 管理页面
   - 创建 BotManagementPage
   - 实现 AddBotWizard
   - 集成到"设置"页面

🔧 6. Napcat 二维码登录
   - WebSocket 流式传输二维码数据
   - 前端实时渲染 QR Code
   - 登录成功后自动跳转
```

### 第三阶段：性能与体验优化（2 周）

```
⚡ 7. 事件驱动队列
   - 实现 SQLAlchemy 钩子
   - 重构 DistributionEngine
   - 性能测试与调优

⚡ 8. 预渲染缓存
   - 扩展 ContentQueue 模型
   - 实现渲染缓存逻辑
   - A/B 对比测试效果

⚡ 9. WebSocket 实时通知
   - 设计消息协议
   - 实现后端推送逻辑
   - 前端集成 StreamProvider
```

### 第四阶段：进阶功能（可选）

```
🚀 10. 智能排期算法
🚀 11. A/B 测试框架
🚀 12. 推送效果分析面板
```

---

## 附录：关键代码片段

### A. 规则创建时关联目标（后端）

```python
# app/routers/distribution.py

@router.post("/distribution-rules", response_model=DistributionRuleResponse)
async def create_distribution_rule(
    rule: DistributionRuleCreate,
    db: AsyncSession = Depends(get_db),
):
    # 1. 创建规则
    db_rule = DistributionRule(**rule.model_dump(exclude={'targets'}))
    db.add(db_rule)
    await db.flush()  # 获取 rule.id
    
    # 2. 批量创建目标关联
    if rule.targets:
        for target_create in rule.targets:
            db_target = DistributionTarget(
                rule_id=db_rule.id,
                **target_create.model_dump()
            )
            db.add(db_target)
    
    await db.commit()
    await db.refresh(db_rule)
    return db_rule
```

### B. 群组选择器组件（前端）

```dart
// frontend/lib/features/review/widgets/bot_chat_selector.dart

class BotChatSelector extends ConsumerWidget {
  final List<int> selectedIds;
  final ValueChanged<List<int>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(botChatsProvider);
    
    return chatsAsync.when(
      data: (chats) => Column(
        children: chats.map((chat) => CheckboxListTile(
          title: Text(chat.displayName),
          subtitle: Text(chat.chatId),
          value: selectedIds.contains(chat.id),
          onChanged: (checked) {
            final newIds = List<int>.from(selectedIds);
            checked ? newIds.add(chat.id) : newIds.remove(chat.id);
            onChanged(newIds);
          },
        )).toList(),
      ),
      loading: () => CircularProgressIndicator(),
      error: (e, _) => Text('加载失败: $e'),
    );
  }
}
```

### C. 事件驱动队列匹配

```python
# app/models.py

from sqlalchemy import event

@event.listens_for(Content, 'after_insert')
def on_content_created(mapper, connection, target):
    """Content 创建后自动触发规则匹配"""
    if target.status == ContentStatus.PULLED:
        # 使用后台任务避免阻塞
        from app.distribution.engine import DistributionEngine
        background_tasks.add_task(
            DistributionEngine.match_and_queue_content,
            content_id=target.id
        )
```

---

## 总结

本设计方案通过 **四层架构** 清晰划分了职责：
1. **BotConfig**: 管理 Bot 账号凭证
2. **BotChat**: 存储 Bot 加入的群组身份
3. **DistributionRule**: 定义内容过滤和推送格式
4. **BotChatRuleConfig**: 连接规则与群组，支持个性化配置

完整使用流程覆盖了从 **Bot 配置** → **规则创建** → **内容入队** → **审批** → **推送** → **监控** 的全链路。

关键优化点聚焦于：
- ✅ **简化操作**: 规则创建时一键选择目标
- ✅ **降低门槛**: 可视化 Bot 配置（无需改环境变量）
- ✅ **提升性能**: 事件驱动 + 预渲染缓存
- ✅ **优化体验**: WebSocket 实时反馈

建议按 **三阶段渐进式实施**，优先打通核心流程，再逐步增强体验和性能。
