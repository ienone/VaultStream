# 设计思路

## 1. 核心理念

BetterShare 旨在解决碎片化内容“存不下、找不着、发不出”的问题。通过极简的输入端（移动端分享/Web 快捷提交），实现跨平台内容的自动化结构化存储与定向分发。

## 2. 系统架构

- 输入层 (Trigger):

    - Material 3 风格 Web 页面。
    - (规划中) 移动端 Share Target 插件。

- 处理层 (Worker):

    - 异步任务队列 (Redis)。
    - 平台适配器 (Adapters) 实现 URL 净化与元数据抓取。

- 存储层 (Database): 
    - PostgreSQL 存储结构化数据。
    - JSONB 存储原始元数据以备回溯。
- 分发层 (Output): 
    - Telegram Bot 自动推送。
    - (规划中) RSS Feed 与个人展示页。

## 3. 关键逻辑
- URL 净化: 自动剥离追踪参数，还原短链接。
- 状态机管理: 严格控制内容从 `抓取` 到 `分发` 的生命周期。
- 分发去重: 基于 `pushed_records` 表确保同一内容不会在同一频道重复出现。
