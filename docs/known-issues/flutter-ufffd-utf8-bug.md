# 已知问题：Flutter/Dart 对合法 U+FFFD 字符误报 UTF-8 编码错误

## 状态：已暂缓（后端 workaround 已上线）

## 问题描述

当后端 API 返回的 JSON 字符串中包含 Unicode 替换字符 `U+FFFD`（�）时，Flutter 客户端报错：

```
Bad UTF-8 encoding (U+FFFD; REPLACEMENT CHARACTER) found while decoding string:
...
The Flutter team would greatly appreciate if you could file a bug...
```

### 触发场景

爬取的网页内容本身讨论编码问题，正文中合法地包含 `U+FFFD` 字符（如文章说明 UTF-8 遇到不认识的字符会转化为 `�`）。

### 根本原因

这是 **Dart SDK 的 bug**。`U+FFFD` 的 UTF-8 编码为 `EF BF BD`，是完全合法的 UTF-8 字节序列。Dart 的 UTF-8 解码器错误地将"字符串中存在 U+FFFD"等同于"字节流中存在畸形编码"，对合法字符报错。

### 尝试过但无效的方案

在 Dio 的 `BaseOptions` 中设置 `responseDecoder` 使用 `utf8.decode(bytes, allowMalformed: true)`，无法消除该错误，说明问题不在 Dio 的解码层，而在更底层的 Dart 运行时。

## 当前暂缓方案

在后端两处清理 `U+FFFD` 字符，从源头避免将该字符发送给客户端：

1. **`backend/app/adapters/universal_adapter.py`** — `_cleanup_markdown()` 中移除 `\ufffd`，新内容入库前即清理
2. **`backend/app/services/content_presenter.py`** — `transform_content_detail()` 中对 `title` 和 `description` 移除 `\ufffd`，覆盖已入库的旧数据

### 副作用

原文中合法的 `�` 字符会被移除。对于讨论编码问题的技术文章，可能丢失少量语义信息（但通常文章会同时标注 `U+FFFD` 文字说明，影响有限）。

## 上报建议

如需正式报告此 bug：

- **报告地址**：https://github.com/dart-lang/sdk/issues
- **最小复现**：启动一个 HTTP 服务返回 `{"text": "\uFFFD"}`，用 Flutter Dio 请求并观察控制台
- **要点**：`EF BF BD` 是合法 UTF-8，解码器不应将其视为编码错误
