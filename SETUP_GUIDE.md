# VaultStream 完整安装指南

此文件提供了VaultStream项目的完整安装和启动步骤。

最后更新: 2026年1月27日

---

## 快速导航

- [Windows 用户](#windows-安装) 
- [Linux/macOS 用户](#linuxmacos-安装)
- [前端开发](#前端开发)
- [故障排除](#故障排除)

---

## Windows 安装

### 前置条件

- Windows 10/11
- Python 3.10 或更高版本（从 [python.org](https://www.python.org/downloads/) 下载）
- 可选：Visual Studio Build Tools（某些 Python 包需要编译）

### 第 1 步：安装 Python

1. 访问 [python.org](https://www.python.org/downloads/)
2. 下载 Python 3.10+ 版本
3. 运行安装程序：
   - ✅ 勾选 "Add Python to PATH"
   - ✅ 勾选 "Install pip"

### 第 2 步：克隆项目

```powershell
git clone https://github.com/yourusername/VaultStream.git
cd VaultStream
```

### 第 3 步：安装后端

```powershell
cd backend
install.bat
```

脚本将：
- 检查 Python 安装
- 创建虚拟环境 (`.venv`)
- 安装 Python 依赖
- 创建配置文件 (`.env`)

### 第 4 步：配置环境

编辑 `backend\.env` 文件（用记事本或 VSCode 打开）：

```dotenv
# Telegram Bot 权限（账号通过 /api/v1/bot-config 创建）
TELEGRAM_ADMIN_IDS=123456,789012
TELEGRAM_WHITELIST_IDS=
TELEGRAM_BLACKLIST_IDS=

# 数据库 (默认即可)
DATABASE_TYPE=sqlite
SQLITE_DB_PATH=./data/vaultstream.db

# 存储 (默认即可)
STORAGE_BACKEND=local
STORAGE_LOCAL_ROOT=./data/media

# API (本地开发默认即可)
API_HOST=0.0.0.0
API_PORT=8000
```

### 第 5 步：启动后端

```powershell
cd backend
start.bat
```

你应该看到：
```
启动 VaultStream
====================

使用 Python: c:\path\to\.venv\python.exe
初始化数据库...
数据库初始化完成
启动 FastAPI 后端...
```

访问：
- 测试页面：http://localhost:8000
- API 文档：http://localhost:8000/docs

### 第 6 步：安装前端

在另一个 PowerShell 窗口：

```powershell
cd VaultStream\frontend
flutter pub get
dart run build_runner build
flutter run -d chrome
```

前端应在 http://localhost:8080 打开

---

## Linux/macOS 安装

### 前置条件

- Python 3.10+
- Bash shell
- `git` 命令行工具

### 第 1 步：安装 Python

Ubuntu/Debian:
```bash
sudo apt update
sudo apt install python3 python3-pip python3.11-venv
```

macOS:
```bash
brew install python@3.11
```

### 第 2 步：克隆项目

```bash
git clone https://github.com/yourusername/VaultStream.git
cd VaultStream
```

### 第 3 步：安装后端

```bash
cd backend
bash install.sh
```

脚本将提示选择安装模式：

```
安装模式选择:
  1. 创建虚拟环境 (.venv)
  2. 使用系统 Python 或 Conda 环境

请选择 (1/2): 1
```

选项 1（推荐）：创建独立虚拟环境
- 不影响系统 Python
- 依赖隔离

选项 2：使用系统 Python
- 适合已有 Conda 环境的用户

### 第 4 步：配置环境

```bash
nano backend/.env
```

编辑以下内容：

```dotenv
# Telegram Bot 权限（账号通过 /api/v1/bot-config 创建）
TELEGRAM_ADMIN_IDS=123456,789012
TELEGRAM_WHITELIST_IDS=
TELEGRAM_BLACKLIST_IDS=

# 其他配置使用默认值即可
```

### 第 5 步：启动后端

```bash
cd backend
bash start.sh
```

你应该看到：
```
启动 VaultStream
=====================

检查虚拟环境...
使用 Python: ./.venv/bin/python
初始化数据库...
数据库初始化完成
启动 FastAPI 后端...
```

访问：
- 测试页面：http://localhost:8000
- API 文档：http://localhost:8000/docs

### 第 6 步：启动 Bot（可选）

在另一个终端：

```bash
cd backend
./.venv/bin/python -m app.bot
```

### 第 7 步：启动 Worker（可选）

在另一个终端：

```bash
cd backend
./.venv/bin/python -m app.worker
```

---

## 前端开发

### 安装 Flutter

官方指南: https://flutter.dev/docs/get-started/install

快速检查：
```bash
flutter doctor
```

应输出：
```
✓ Flutter (Channel stable, 3.10.x)
✓ Dart (version 3.x.x)
✓ Android toolchain (if developing for Android)
✓ Xcode (if developing for iOS on macOS)
```

### 启动前端

```bash
cd VaultStream/frontend

# 1. 获取依赖
flutter pub get

# 2. 代码生成
dart run build_runner build

# 3. 运行应用
flutter run -d chrome              # Web 版本 (推荐开发)
# 或
flutter run -d windows             # Windows Desktop
flutter run -d emulator            # Android 模拟器
flutter run -d iphone              # iOS 模拟器 (macOS only)
```

更多详情见：[frontend/README.md](frontend/README.md)

---

## 数据位置

| 内容 | 位置 |
|------|------|
| SQLite 数据库 | `./data/vaultstream.db` |
| 媒体存储 | `./data/media/` |
| 日志文件 | `./logs/vaultstream.log` |
| 配置文件 | `backend/.env` |
| Python 虚拟环境 | `backend/.venv/` (可选) |

---

## 生产部署（可选）

### 使用 Systemd（Linux 服务器）

```bash
# 部署服务配置
sudo bash backend/scripts/deploy_services.sh

# 管理服务
sudo systemctl start vaultstream-api
sudo systemctl stop vaultstream-api
sudo systemctl status vaultstream-api

# 查看日志
sudo journalctl -u vaultstream-api -f
```

详见：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

---

## 获取帮助

1. 查阅文档：
   - [README.md](README.md) - 项目总览
   - [TASKS.md](TASKS.md) - 开发任务
   - [frontend/README.md](frontend/README.md) - 前端指南
   - [docs/API.md](docs/API.md) - API 文档

2. GitHub Issues：报告问题或建议功能


---

需要帮助？ 提交 Issue 或联系维护者。

版本: v1.0.0  
最后更新: 2026年1月27日
