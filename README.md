# BetterShare - 更好的分享系统

BetterShare 是一个用于储存记录和分享多平台内容的系统，未来将支持通过web界面/app方便的记录存档内容，以及快捷干净的分享。
系统设计注重解耦和可扩展性，方便添加新的内容平台适配器。

## 项目结构

```text
app/
├── adapters/          # 平台解析适配器 (B站, X等)
├── api.py             # FastAPI 路由定义
├── bot.py             # Telegram Bot 逻辑
├── models.py          # SQLAlchemy 数据库模型
├── worker.py          # 异步抓取任务处理器
└── utils.py           # 解耦的工具函数 (URL规范化, 文本格式化)
docs/                  # 详细文档
static/                # 前端测试页面 (Material 3)
```

## 使用方法

### 1. 启动服务

```bash
./install.sh
cp .env.example .env  # 配置 TELEGRAM_BOT_TOKEN 等
./start.sh
```

### 2. 提交分享

- Web 界面: 访问 `http://localhost:8000`。支持直接输入 BV/av/cv 号。
- API 提交:

```bash
curl -X POST http://localhost:8000/api/v1/shares \
  -H "Content-Type: application/json" \
  -d '{"url": "BV1xx411c7XD", "tags": ["技术", "教程"]}'
```

### 3. Bot 交互

- `/get [tag]` - 获取并推送一条内容到频道。
- `/status` - 查看系统状态。

## 📚 详细文档

- [设计思路](docs/DESIGN.md)
- [数据库结构](docs/DATABASE.md)
- [开发待办清单](docs/TODO.md)