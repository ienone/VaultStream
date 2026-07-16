# VaultStream

![Python](https://img.shields.io/badge/Python-3.11+-blue?logo=python&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-%5E3.41.1-02569B?logo=flutter&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-003B57?logo=sqlite&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 功能概览

**内容采集**
- 支持 Bilibili、Twitter/X、小红书、知乎、微博，以及任意网页（通用适配器 + LLM 提取）
- 自动解析标题、正文、作者、标签、媒体文件
- 图片自动转码 WebP，视频/GIF 支持 ffmpeg 处理
- 平台收藏自动同步（知乎收藏夹、小红书收藏、Twitter/X 书签）

**存档管理**
- SQLite 本地存储，FTS5 全文检索 + 标签筛选
- 内容状态管理（待解析 / 成功 / 失败 / 已归档）
- NSFW 标记、标签筛选和结构化内容状态

**自动分发**
- 基于规则的内容推送（按平台、标签匹配）
- 支持 Telegram Channel/Group、QQ（Napcat/OneBot 11）
- 推送去重、失败重试、优先级排序、排期投递

**多端管理**
- Flutter Web / Desktop / Mobile 客户端
- 响应式布局，Material 3 主题
- 动态信息流、收藏库、自动化、通知与设置

## 架构

Flutter + FastAPI + SQLite；当前模块和职责以文档索引与代码为准。

文档索引：[docs/README.md](./docs/README.md)

---

## 部署

### 前端

- 每个 [Release](https://github.com/ienone/VaultStream/releases) 提供安卓端apk
- 前端网页版则在后续步骤中从package中拉取部署。参见 [docker-compose.yml](https://raw.githubusercontent.com/ienone/VaultStream/main/backend/docker-compose.yml)

| 文件 | 说明 |
|------|------|
| `app-arm64-v8a-release.apk` | Android 客户端 (64位现代手机，**推荐**) |
| `app-armeabi-v7a-release.apk` | Android 客户端 (32位老旧手机) |
| `app-x86_64-release.apk` | Android 客户端 (安卓模拟器) |

### 参考部署流程

如果希望通过公网域名（如 `https://vaultstream.your-domain.com`）对外提供服务，参考以下 **1-2-3** 顺序操作。
> 注：如果是局域网或内网穿透纯 IP 用户，请直接跳到 **第 3 步** 并在 `.env` 里填写您的 IP 即可。

#### 1. 域名解析 (DNS)
前往域名提供商（如阿里云、腾讯云、Cloudflare）控制台
- 添加一条 **A 记录**。
- **主机记录**（前缀）填写 `vaultstream`（或者任意你喜欢的名字）。
- **记录值** 填写您这台服务器的公网 IP 地址。
- 保存并等待解析生效（通常几分钟）。

#### 2. 前置 Nginx 反向代理与 HTTPS


**① 编写初始 Nginx 配置文件供后续申请证书使用**

在宿主机创建 Nginx 配置文件（例如 `/etc/nginx/conf.d/vaultstream.conf` 或 `/etc/nginx/sites-available/vaultstream`）：

```nginx
server {
    listen 80;
    server_name vaultstream.your-domain.com; # 请替换为你的真实域名

    location / {
        # 转发流量到本地 Docker 的 18282 端口
        proxy_pass         http://127.0.0.1:18282;  
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
```

**② 申请并部署 SSL 证书**
可以使用 `certbot` 签发（它会自动识别到配置文件，并填好真实的证书路径）：
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d vaultstream.your-domain.com
```

#### 3. 部署 Docker 服务

```bash
# 1. 创建工作目录并下载编排文件
mkdir -p /opt/vaultstream && cd /opt/vaultstream
curl -O https://raw.githubusercontent.com/ienone/VaultStream/main/backend/docker-compose.yml
curl -o .env https://raw.githubusercontent.com/ienone/VaultStream/main/backend/.env.example
```

编辑 `.env` 配置文件，填入域名：

```ini
BASE_URL=https://vaultstream.your-domain.com            # 用于生成图片链接
CORS_ALLOWED_ORIGINS=https://vaultstream.your-domain.com # 允许跨域请求的前端源，一般同上
```

启动服务：

```bash
docker compose up -d

# 获取初始化 API 密钥（用于前端首次打开时对接后端）
docker logs vaultstream-api
```

> 大模型 LLM Key、Bot Token 等其余配置，均可在前端图形网页中配置，不再需要写入 `.env` 文件。

### 从源码构建

```bash
git clone https://github.com/ienone/VaultStream.git
cd VaultStream/frontend
flutter pub get && dart run build_runner build --delete-conflicting-outputs
flutter build web --release

cd ../backend && cp .env.example .env
docker compose up -d
```

---

## 使用方式

1. 访问前端页面，通过界面添加内容链接、管理标签、浏览存档；分享链接等内容时通过系统分享功能，接入应用
2. 在前端「自动化 → 分发」中管理规则、目标和分发队列
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
# 1. 按照 Napcat 官方文档完成部署和扫码登录
# 2. 进入 Napcat 的 Web UI / 配置界面
# 3. 在【网络配置】中，点击【新建】 -> 选择【HTTP服务器】
# 4. 监听主机可填 0.0.0.0，端口任意（如 3000），可选择设置一个 Token
```

**在 VaultStream 中配置：**

1. 打开 **设置 → 推送与通知**
2. 选择平台为 **QQ (Napcat)**
3. 填入 Napcat 的服务地址（如果是同一台服务器且端口为 3000，填 `http://127.0.0.1:3000` 或 `http://宿主机IP:3000`。由于 Docker 隔离，可能需要填写 `http://host.docker.internal:3000` 或直接填分配的局域网 IP）
4. （可选）填写刚才在 Napcat 设置的 Token
5. 保存后在「自动化 → 分发」中同步目标并管理分发规则

---

## 推送规则说明

内容入库后，VaultStream 通过「**分发规则**」决定将哪些内容推送到哪些群组。

### 规则工作流

```
内容入库 → 匹配规则 → 进入分发队列 → 策略过滤/确认 → 推送至目标
```

### 配置步骤

1. **进入「自动化 → 分发」** → 打开规则管理
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
│   │   ├── routers/         # FastAPI 路由
│   │   ├── services/        # 业务编排
│   │   ├── repositories/    # 数据访问
│   │   ├── adapters/        # 平台、浏览器和存储适配
│   │   ├── tasks/           # 后台任务
│   │   ├── models/          # ORM 模型
│   │   ├── schemas/         # 请求/响应 Schema
│   │   ├── media/           # 媒体处理
│   │   └── core/            # 配置、数据库、日志和事件
│   ├── tests/               # 正式 pytest 测试
│   ├── manual_tests/        # 本地平台探针（不进入 CI）
│   ├── data/                # 本地运行数据（Git 忽略）
│   └── migrations/          # 当前架构管理文件
├── frontend/
│   ├── lib/features/        # 动态、收藏库、自动化、Agent、设置等
│   └── test/                # Flutter 单元与 Widget 测试
├── docs/                    # 现状、计划、问题和知识资料
└── scripts/                 # 可重复的仓库维护/验证脚本
```

---

## 后续规划

当前计划与目标形态统一维护在 [docs/plans/](./docs/plans/README.md)。README 不再维护容易与代码漂移的独立 Roadmap；具体功能是否已经实现，以代码、现状文档和可重复验证结果为准。

---

## 开源致谢

收藏同步模块的 API 调用模式参考了以下项目（并已在对应源码文件头部保留引用说明）：

- [xiaohongshu-cli](https://github.com/jackwener/xiaohongshu-cli) (Apache-2.0)
- [twitter-cli](https://github.com/jackwener/twitter-cli) (Apache-2.0)
- [ZhihuCollectionsPro](https://github.com/ienone/ZhihuCollectionsPro) (MIT)

---


## 许可证

MIT License
