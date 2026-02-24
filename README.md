# VaultStream

![Python](https://img.shields.io/badge/Python-3.11%2B-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.10%2B-blue)
![License](https://img.shields.io/badge/License-MIT-green)

私有内容存档与分享系统。从多个平台采集内容，本地化存储，按规则自动推送到 Telegram / QQ 等渠道。

---

## 功能概览

**内容采集**
- 支持 Bilibili、Twitter/X、小红书、知乎、微博，以及任意网页（通用适配器 + LLM 提取）
- 自动解析标题、正文、作者、标签、媒体文件
- 图片自动转码 WebP，视频/GIF 支持 ffmpeg 处理

**存档管理**
- SQLite 本地存储，FTS5 全文检索 + 标签筛选
- 内容状态管理（待解析 / 成功 / 失败 / 已归档）
- NSFW 标记与内容审批流

**自动分发**
- 基于规则的内容推送（按平台、标签匹配）
- 支持 Telegram Channel/Group、QQ（Napcat/OneBot 11）
- 推送去重、失败重试、优先级排序、排期投递

**多端管理**
- Flutter Web / Desktop / Mobile 客户端
- 响应式布局，Material 3 主题
- 收藏浏览、审批面板、仪表板、分发规则配置

## 架构

flutter+fastapi+sqlite

---

## 部署

每个 [Release](https://github.com/ienone/VaultStream/releases) 提供开箱即用的部署包，前端网页已内嵌。

| 文件 | 说明 |
|------|------|
| `vaultstream-vX.X.X.zip` | 完整部署包（前端网页 + 后端） |
| `app-release.apk` | Android 客户端 |

> **发布新版本**：在 main 分支推送 tag 即可触发 CI 自动构建：
> ```bash
> git tag v1.0.0 && git push origin v1.0.0
> ```

### 快速部署（推荐）

```bash
# 1. 下载并解压
unzip vaultstream-vX.X.X.zip && cd backend

# 2. 配置（仅需修改两项）
cp .env.example .env
```

编辑 `.env`，填写你的域名：

```ini
BASE_URL=https://your-domain.com            # 用于生成图片链接，不设置则图片无法加载
CORS_ALLOWED_ORIGINS=https://your-domain.com
```

```bash
# 3. 启动
docker compose up -d

# 4. 获取 API 密钥（首次启动自动生成，复制后填入前端连接页）
docker logs vaultstream
```

LLM Key、Bot Token、平台 Cookie 等均可在前端引导界面中配置，无需写入 `.env`。

### Nginx 反向代理

参考配置见 [`backend/systemd/nginx.conf.example`](backend/systemd/nginx.conf.example)：

```nginx
# 前端（Nginx 直接托管 backend/static/，不经过 FastAPI）
root /opt/vaultstream/backend/static;
location / { try_files $uri $uri/ /index.html; }

# 媒体文件（直接读取，带静态缓存）
location /media/ { alias /opt/vaultstream/backend/data/media/; expires 30d; }

# 后端 API（SSE 必须关闭 buffering）
location /api/ { proxy_pass http://127.0.0.1:8000; proxy_buffering off; }
```

### 从源码构建

```bash
git clone https://github.com/ienone/VaultStream.git
cd VaultStream/frontend
flutter pub get && dart run build_runner build --delete-conflicting-outputs
flutter build web --release

# 将前端产物复制到 backend/static/（Nginx 直接从此目录托管）
cp -r build/web ../backend/static

cd ../backend && cp .env.example .env
docker compose up -d
```

---

## 使用方式

1. 访问前端页面，通过界面添加内容链接、管理标签、浏览存档
2. 在前端「审批与分发」页面配置推送规则和目标群组，内容解析成功后自动推送
3. （可选）配置 Telegram Bot 或 QQ Bot，直接向 Bot 发送链接即可入库

API 文档：启动后访问 `http://localhost:8000/docs`

---

## 推送机器人配置（可选）

### Telegram Bot

1. 在 Telegram 中找到 **[@BotFather](https://t.me/BotFather)**，发送 `/newbot`，按提示创建后获得 **Bot Token**（格式：`12345678:ABC-DEF...`）
2. 打开 VaultStream 前端，首次访问时**引导界面**会引导填写 Token；或在 **设置 → 推送与通知** 中配置
3. 配置完成后向 Bot 发送 `/start`，Bot 即可接收链接并入库

> **获取自己的 Telegram 用户 ID**：向 [@userinfobot](https://t.me/userinfobot) 发送任意消息即可获取。在管理员 ID 字段填入后，Bot 将只响应该用户的命令。

### QQ Bot（通过 Napcat） 

QQ Bot 需要先在服务器上独立部署 [NapCatQQ](https://github.com/NapNeko/NapCatQQ)（基于 QQNT 协议的 OneBot 11 实现）。

**部署 Napcat（与 VaultStream 同服务器）：**

```bash
# 参考 Napcat 官方文档
# 启动后默认监听 3000 端口（HTTP 模式）
# 扫码登录 QQ 账号后即可使用
```

**在 VaultStream 中配置：**

1. 打开 **设置 → 推送与通知**
2. 选择平台为 **QQ (Napcat)**
3. 填入 Napcat 服务地址（例如 `http://127.0.0.1:3000`）
4. 保存后即可在「审批与分发 → Bot 群组」中同步 QQ 群列表

---

## 推送规则说明

内容入库后，VaultStream 通过「**分发规则**」决定将哪些内容推送到哪些群组。

### 规则工作流

```
内容入库 → 匹配规则 → 进入推送队列 → 审批（可选）→ 推送至目标群组
```

### 配置步骤

1. **进入「审批与分发」** → 点击「新建规则」
2. **设置匹配条件**（可组合）：
   - 来源平台（Bilibili / 知乎 / 微博 等）
   - 标签（如 `技术`、`设计`）
   - NSFW 过滤
3. **绑定推送目标**：将规则关联到一个或多个 Bot 群组/频道
4. **选择审批模式**：
   - `自动推送` — 匹配后立即推送，无需人工审核
   - `待审阅` — 进入待审队列，手动点击确认后推送

### 示例

| 规则名 | 匹配条件 | 推送目标 | 模式 |
|--------|---------|---------|------|
| 知乎精选 | 平台=知乎，标签=`技术` | TG 频道 A | 自动 |
| 微博观察 | 平台=微博 | TG 群组 B | 待审阅 |

> **提示**：同一条内容可同时匹配多条规则，会分别推送到各自目标。

---

## 项目结构

```
VaultStream/
├── backend/
│   ├── app/
│   │   ├── adapters/        # 平台解析器（bilibili, twitter, zhihu 等）
│   │   ├── routers/         # API 路由
│   │   ├── services/        # 业务逻辑
│   │   ├── repositories/    # 数据访问层
│   │   ├── distribution/    # 分发引擎 + 队列 Worker
│   │   ├── worker/          # 后台任务处理
│   │   ├── bot/             # Telegram Bot
│   │   ├── push/            # 推送服务（Telegram / Napcat）
│   │   ├── media/           # 媒体下载与转码
│   │   ├── core/            # 配置、数据库、日志、存储、事件总线
│   │   ├── models.py        # ORM 模型
│   │   ├── schemas.py       # 请求/响应 Schema
│   │   └── main.py          # FastAPI 入口
│   ├── data/                # SQLite 数据库 + 媒体文件
│   ├── migrations/          # 数据库迁移
│   ├── systemd/             # Systemd 服务配置
│   ├── Dockerfile
│   └── docker-compose.yml
├── frontend/                # Flutter 客户端
│   └── lib/features/        # 收藏、审批、仪表板、设置
└── docs/                    # API、架构、适配器文档
```

---

## Roadmap

以下功能在计划中，尚未实现：

- **预测性返回手势** — 预测用户返回手势，提前加载上一页，提升操作便利性
- **RSS/Atom 订阅** — 支持 RSS 源自动抓取，全文入库，生成摘要
- **多源自动同步** — 绑定平台账号，自动同步收藏夹和关注更新
- **AI Agent 巡逻** — 基于用户偏好自动发现高价值内容，判断是否存档/推送
- **RAG 语义检索** — 对存档内容进行向量化，支持自然语言问答
- **Telegram 群组深度集成** — 全量存档群内链接，或由 LLM 筛选高价值内容

---


## 许可证

MIT License
