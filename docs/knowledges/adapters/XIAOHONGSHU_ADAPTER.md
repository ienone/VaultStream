# 小红书内容适配器文档

## 文档状态

active

## 适用范围

- 平台：小红书
- 当前代码：`backend/app/adapters/xiaohongshu.py`
- 当前类：`XiaohongshuAdapter`
- 测试：`backend/tests/test_public_parser_integrity.py`

## 背景

小红书内容解析通常受 Cookie、签名、SSR 数据和反爬策略影响。该文档记录平台知识，不直接代表当前开发计划。

## 当前事实

当前适配器由 `XiaohongshuAdapter` 实现，并输出标准 `ParsedContent`。下文平台细节保留为知识库参考；如与代码不一致，以当前代码和测试为准。

## 与代码的关系

- 适配器注册：`backend/app/adapters/__init__.py`
- 解析实现：`backend/app/adapters/xiaohongshu.py`
- 笔记实现：`backend/app/adapters/xiaohongshu_parser/note_parser.py`

## 使用方式

修改小红书解析前，应先确认 Cookie/签名路径是否仍有效；涉及新字段或新 URL 类型时应先建 plan 并补测试。

## 收藏同步访问参数（2026-09-10）

真实收藏接口 `/api/sns/web/v2/note/collect/page` 的 `data.notes[]` 返回 `xsec_token`。收藏 fetcher 必须将其 URL 编码后保留在笔记链接上，再交给现有解析流程；只有 note_id 的裸链接可能无法读取详情。两条真实收藏在修复前均报缺少 xsec_token，保留该字段后都成功取得正文、作者与媒体。当前取样响应没有 xsec_source，不虚构其字段。

## 已知限制

- Cookie 和签名策略容易过期。
- 页面 SSR 结构可能变化。
- 下文历史策略需要按当前代码和真实样本复核。

VaultStream 的小红书适配器通过调用小红书内部 API（配合 `xhshow` 库进行签名）或解析网页 SSR 数据，支持抓取笔记（Note）、视频（Video）以及用户主页（User Profile）。

---

## 1. 支持的 URL 模式

| 模式 | 示例 | 备注 |
| :--- | :--- | :--- |
| 笔记详情 (Web) | `xiaohongshu.com/explore/{note_id}` | 支持 `discover/item` 兼容 |
| 短链接 (APP 分享) | `xhslink.com/{code}` | 自动解析还原 |
| 用户主页 | `xiaohongshu.com/user/profile/{user_id}` | 部分主页可匿名直读；保留链接提供的 `xsec_token` |

---

## 2. 解析逻辑与策略

带 `xsec_token` 的笔记在无账号时直接读取公开 SSR；有账号时沿用签名 API，失败后尝试 SSR。无访问 token 时不猜测或伪造 token。

用户主页在无账号时读取 SSR；保存账号时保留现有 `otherinfo` 签名 API。匿名资料取自 `user.userPageData`，同时核对 `user.noteQueries[].userId`、加载状态与资料结果。主页不能用推荐用户或登录者资料替代。2026-09-19 样本 `6a55a850000000000e03cc02` 无 token/无 Cookie 成功，三次完整解析中位数约 0.40 秒；另一个样本被重定向到空壳，仍明确失败，不能推断所有主页免登录。

### 2.1 签名 API 请求 (Hybrid)
适配器集成了 `xhshow` 库来生成必要的签名头（如 `x-s`）。
- 主要接口: `/api/sns/web/v1/feed` (笔记)、`/api/sns/web/v1/user/otherinfo` (用户信息)。
- 优势: 返回数据结构最完整，包含高清视频流、互动数等。

### 2.2 SSR 数据提取

使用网页导航请求头访问原文，从 `window.__INITIAL_STATE__.note.noteDetailMap[note_id].note` 提取目标。2026-09-19 对照发现，仅 User-Agent/Accept 得到 HTTP 200 空壳；加入正常浏览器的 client hints 与 `Upgrade-Insecure-Requests` 后，同一图文与视频笔记返回详情。不能仅凭 HTTP 200 判定成功。

- 必须匹配请求 note_id；不再选择响应中的第一条推荐笔记。
- 共用状态提取器只转换实测出现的 JavaScript 值 `undefined`、`new Set([])`，正文字符串中的同名文字保持原样；不执行网页脚本。
- SSR 的 `userId`、`xsecToken` 和 H.264 流 `masterUrl` 在边界转换为 API 字段，避免作者丢失和视频被误存为图文。
- 网页真实 `/api/sns/web/v1/feed` 响应已确认 `data.items[].id` 与 `note_card.note_id`；API 解析同样按目标身份选择。

匿名实测图文取回 18 张图片；视频取回封面与 H.264 视频地址，作者 ID 均存在。图片和视频各读取 1 KB 得到对应媒体类型；这不代表完成媒体全量下载。详情见[验收记录](../../plans/2026-09-19-public-parser-exploration.process.md)。

---

## 3. 核心功能特性

### 3.1 媒体获取
- 多图抓取: 自动识别图文笔记中的所有图片，并优先选择高清、无水印版本。
- 视频解析: 从平台返回的 H.264 列表读取首个有效视频 URL，保留该流的尺寸和时长，并提取封面；不宣称一定是平台最高画质。
- WebP 转化: 适配系统媒体处理层，自动本地化缓存图片。

### 3.2 文本净化
- 标题隔离: 自动区分笔记标题与正文。
- 标签剥离: 识别 `#话题#` 格式并将其提取到 `source_tags`，同时在正文中净化掉这些干扰字符。
- Markdown 渲染: 自动将图文分布渲染为结构化的 Markdown 存档。

---

## 4. 数据映射 (stats)

| 统一字段 | 对应小红书字段 | 说明 |
| :--- | :--- | :--- |
| `like` | `liked_count` | 点赞数 |
| `collect` | `collected_count` | 收藏数 |
| `comment` | `comment_count` | 评论数 |
| `share` | `share_count` | 分享数 |

---

## 5. 配置说明

### 5.1 Cookie 配置
签名 API 与账号功能使用有效 Cookie。带有效 `xsec_token` 的公开笔记可独立读取 SSR，本轮已验证无 Cookie 图文与视频；这不代表所有分享链接都免登录。

```env
# .env 文件
XIAOHONGSHU_COOKIE="webId=...; gid=...; a1=...; web_session=...;"
```

---

## 6. 开发者参考

- 核心代码: `backend/app/adapters/xiaohongshu.py`
- 主要逻辑: 
    - `fetch_note`: 按账号和访问 token 选择 API / SSR。
- `build_note_archive`: 跨平台通用的归档模型构建流程。

## 7. 2026-07-28 真实验证与字段修正

- 两个带有效 `xsec_token` 的图文笔记样本均通过签名 API 解析。
- 平台返回的 `4万`、`1.7万` 等紧凑计数在适配器边界转换为整数，避免数据库通用统计列落为 0。
- 布局由实际媒体决定：存在视频为 `video`，否则为 `gallery`。
- 作者头像只写入作者字段和私有归档，不再计入正文图片数量、正文媒体或封面。
- 页面可见并不意味着去掉 `xsec_token` 后仍可稳定解析；真实样本必须保留分享 URL 中该参数。

## 内容身份与段落（2026-09-10）

- 笔记和用户主页的 `clean_url` 按平台对象 ID 生成，不含访问 token；原始 `Content.url` 保留实际访问参数，解析前从原始链接提取。访问 token 更新不再改变内容去重身份。当前项目在修复前没有已入库小红书记录；其他旧库若已有带 token 的 canonical_url，升级前需单独审查和迁移，不能直接宣称历史数据已合并。
- 去除话题标签只整理行内空白，保留原正文段落；实际样本原有 12 个换行，最后一行纯话题移除后保留 11 个换行，旧实现压成 0 个换行。

收藏分页必须有明确 notes 列表与 boolean has_more；有下一页时游标必须非空且本轮未使用。超过请求页大小不截断后推进，返回可诊断错误以避免丢失页尾；缺少 note_id 同样不默默跳过。登录态响应更新通过配置原值条件写入，不覆盖新的登录。
