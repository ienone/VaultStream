# 已知问题：博客代码块行号解析错误

## 问题描述

通用解析器 (`UniversalAdapter`) 在解析包含代码高亮的博客文章时，会将代码块中的行号（1、2、3 等）错误地当作代码内容一起提取，导致存储的 Markdown 内容格式混乱。

### 表现

- 代码块显示时，行号与代码混在一起
- 代码块内容开头出现连续的数字（如 "32 33 34 35..."）
- 代码缩进和格式丢失

### 根本原因

许多博客框架（如 Hexo、Jekyll、Hugo 等）使用表格结构来显示带行号的代码块：

```html
<figure class="highlight c">
  <table>
    <tr>
      <td class="gutter">
        <pre>
          <span class="line">1</span><br>
          <span class="line">2</span><br>
        </pre>
      </td>
      <td class="code">
        <pre>
          <span class="line">/* code here */</span><br>
          <span class="line">if (condition) { ... }</span><br>
        </pre>
      </td>
    </tr>
  </table>
</figure>
```

`Crawl4AI` 的 `DefaultMarkdownGenerator` 无法识别这种结构，会将 `td.gutter` 中的行号和 `td.code` 中的代码一起提取。

## 测试用例

以下链接可用于复现此问题：

1. **Hexo 博客**
   - URL: https://csdn.fjh1997.top/2025/10/20/%E7%94%A8python%E6%A8%A1%E6%8B%9F%E7%9A%84MultiByteToWideChar%E7%84%B6%E5%90%8EWideCharToMultiByte%E5%87%BA%E9%94%99%E6%83%85%E5%86%B5/
   - 特点: 多个长代码块，使用 Hexo highlight.js

2. **个人博客**
   - URL: https://blog.zhanghai.me/fixing-line-editing-on-android-8-0/
   - 特点: 短代码块，行号显示在左侧

## 可能的解决方案

### 方案 1: HTML 预处理

在调用 `DefaultMarkdownGenerator` 之前，预处理 HTML 移除行号元素：

```python
def _preprocess_code_blocks(self, node):
    # 移除 td.gutter 等行号元素
    for elem in node.select('td.gutter, .line-numbers-rows, .lineno'):
        elem.decompose()
    
    # 处理 figure.highlight 表格结构
    for figure in node.select('figure.highlight'):
        code_td = figure.select_one('td.code')
        if code_td:
            # 提取纯代码并重建 pre > code 结构
            ...
```

**问题**: 尝试过此方案，但实际效果不佳，可能是因为：
- `DefaultMarkdownGenerator` 在内部又做了一次 HTML 解析
- 或者预处理后的 HTML 结构仍然不被正确识别

### 方案 2: 后处理 Markdown

解析完成后，使用正则表达式清理代码块中的行号：

```python
def _cleanup_code_blocks(self, markdown):
    # 移除代码块开头的连续数字行
    pattern = r'```(\w*)\n(\d+\n)+```'
    # ...
```

**问题**: 难以准确区分真正的行号和代码中的数字内容

### 方案 3: 自定义 Markdown 生成器

不使用 `DefaultMarkdownGenerator`，而是使用 `markdownify` 或自定义转换器：

```python
from markdownify import markdownify as md

class CustomConverter(MarkdownConverter):
    def convert_figure(self, el, text, convert_as_inline):
        # 自定义处理 figure.highlight
        ...
```

### 方案 4: 平台特定解析器

为常见博客平台（Hexo、Jekyll、Hugo 等）创建专门的适配器，类似于现有的知乎、B站适配器。

## 临时解决方案

目前用户可以：
1. 手动编辑内容，清理代码块
2. 对于重要内容，使用原始链接查看

## 相关文件

- `backend/app/adapters/universal_adapter.py` - 通用适配器
- `crawl4ai.markdown_generation_strategy.DefaultMarkdownGenerator` - Crawl4AI 的 Markdown 生成器
