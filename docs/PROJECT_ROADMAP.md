# VaultStream 项目总结与未来规划

## 1. 项目概览

VaultStream 是一个私有化内容归档与分发系统，旨在帮助用户保存来自多个社交平台的高价值内容，提供统一的浏览体验，并支持推送到其他渠道（如 Telegram）。

### 技术栈
- 前端: Flutter (Mobile/Desktop/Web)，基于 Riverpod 状态管理，Material 3 设计风格。
- 后端: Python (FastAPI)，异步架构。
- 数据库: SQLite (轻量级，支持 FTS5 全文搜索)。
- 存储: 本地文件系统 (LocalStorage)，支持图片转码 (WebP) 和视频下载。
- 任务队列: 基于 SQLite 的持久化队列，支持重试与死信处理。

## 2. 现有功能

### 2.1 支持平台及文档
见各平台详细适配说明：

| 平台 | 解析能力 | 文档链接 | 备注 |
| :--- | :--- | :--- | :--- |
| Bilibili | 视频、专栏、动态 (Opus) | [BILIBILI_ADAPTER.md](adapters/BILIBILI_ADAPTER.md) | 支持完整图文动态归档 |
| Twitter/X | 推文 (FxTwitter) | [TWITTER_ADAPTER.md](adapters/TWITTER_ADAPTER.md) | 免登录获取多图/视频 |
| 微博 | 博文 (Status/User) | [WEIBO_ADAPTER.md](adapters/WEIBO_ADAPTER.md) | 支持长文及移动端链接还原 |
| 知乎 | 回答/文章 (Article/Answer) | [ZHIHU_ADAPTER.md](adapters/ZHIHU_ADAPTER.md) | 优化 API/HTML 差异化解析 |
| 小红书 | 笔记、视频、用户 | [XIAOHONGSHU_ADAPTER.md](adapters/XIAOHONGSHU_ADAPTER.md) | 支持笔记图文和视频 |
| 通用 | 任意网页 | [UNIVERSAL_ADAPTER.md](adapters/UNIVERSAL_ADAPTER.md) | AI 驱动的智能解析 |

### 2.2 前端功能 (Collection)
- 瀑布流/网格视图: 自适应布局，支持卡片悬浮效果。
- 详情页:
    - 多媒体浏览: 支持图片轮播 (PageView) 和全屏缩放 (InteractiveViewer)。
    - 视频播放: 内置视频播放器 (Chewie)，支持微博/Twitter/B站视频播放。
    - 富文本渲染: 解析 Markdown 格式的归档内容 (B站/微博/知乎长文)。
    - 自适应布局: 宽屏模式下采用左右分栏，左侧媒体右侧信息。
- 交互: 支持复制链接、跳转原文、编辑标签、删除内容。

## 3. 开发文档
- [ARCHITECTURE.md](ARCHITECTURE.md) - 系统架构设计
- [DATABASE.md](DATABASE.md) - 数据库模型与迁移说明
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) - 开发规范与实践建议
- [LIGHTWEIGHT_DEPLOYMENT.md](LIGHTWEIGHT_DEPLOYMENT.md) - 轻量级部署指南

## 4. 未来开发方向

### 4.1 前端增强
*   仪表盘 (Dashboard): 可视化统计、存储占用监控、后台任务实时状态。
*   分配流 (Review): 专门的审核界面，一键触发 Telegram 推送。
*   设置中心: 可视化配置 API Token、Cookie 以及外观主题。

### 4.2 平台扩展
*   YouTube/Instagram: 集成更多海外主流平台。
*   通用网页: 基于 Readability 提取任意网页主体内容。

### 4.3 系统优化
*   适配器插件化: 核心引擎与平台规则解耦，便于热更新。
*   移动端集成: 实现 iOS/Android 系统级分享菜单直接归档。

## 5. 总结

VaultStream 已具备核心的“采集-解析-归档-展示”闭环能力。最近的优化平衡了 API 稳定性与数据完整性，并统一了各平台文档体系。接下来的重点将转向提升管理便捷性和移动端交互体验。

