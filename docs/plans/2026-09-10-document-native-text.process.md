# 文档原生文本阅读与页码引用：执行记录

## 状态

in_progress。原生 PDF 上传、提取、阅读、页码搜索及 Agent 读取工具已实现并完成样本验收；完整真实场景 Goal 仍未完成。

## 已实现

- pypdf 6.18.0 为正式约束依赖。独立子进程提取，最多并发 2 个；单文件 64 MiB、500 页、200 万字符、60 秒上限。原文件始终保留，不执行 OCR。
- PDF 捕获后自动调度 `document_extract`，手动入口返回 202 与 run_id；任务结果区分总页数、含原生文本页数。提取完成后再按既有开关调度语义索引。
- 原生文本按文件资产与页码保存为 rich_payload.chunks。读取、搜索、索引和 Agent 核对当前资产与变体；保存说明独立保留。
- 提取期间不持有数据库事务；提交时核对内容版本和原变体身份。结果替换与旧 embedding 删除同一事务提交。摘要更新保留 PDF 页、章节与字幕；摘要源版本冲突返回 409。
- document-text API 返回已校验 DTO，私有提取元数据不进入媒体 manifest。前端支持多文件选择、页码切换、文本复制、重新提取和任务入口。
- 全局搜索新增文档页码分组，支持文本精确召回与现有向量召回。结果进入 `/collection/:id?document_asset=...&page=...`。Agent `read_content` 支持文档资产、页码及长页偏移，引用卡片保留页码。

## 实际验收

- 自制无私人信息的中文 PDF：2 页中文、1 页仅图片、1 页空白。实际提取为 partial / 4 页 / 2 页原生文本，中文首尾均完整。
- pypdf 官方 multicolumn.pdf：3 页均有文本。布局模式会交错左右栏，已根据实际渲染与提取对照改用 plain 模式，该样本先完成左栏再进入右栏。不外推为任意复杂版面均能正确恢复顺序。
- 官方加密 PDF 返回 encrypted；空白页原先触发 KeyError 导致整份损坏误判，已修复。
- 真实 `/captures/files` 上传中文与多栏文件到内容 19，资产 49/50。共 7 页中 5 页原生文本；6 个索引单元实际为 indexed（全局说明 1 + 文本页 5）。没有启用的自动审批规则或分发目标，没有对外发送。
- “海棠书签”通过真实搜索命中内容 19、资产 49、第 2 页；Agent 本地读取工具返回完整原页和 route。未调用 Agent 模型读取私人收藏。
- 浏览器普通入口验证：搜索结果进入正确文件第 2 页，自动滚动至正文；390×844 下翻页、中文换行、页末完整；第 3 页显示未提取原生文本。
- 独立 Python 3.13.15 环境按完整 requirements-dev/constraints 安装成功，pip check 与 pip-audit 通过。后端测试使用根 .venv（Python 3.11.16），不宣称已完成 Python 3.13 全套测试。

## 尚待完成

- 最终回归与最新 JS Web 构建已完成：75 项后端回归、11 项前端回归、Flutter analyze、OpenAPI 150 端点/57 动作 contract 通过。新增摘要版本冲突和原页保留回归通过。
- Agent 引用 DTO 的文件名、页码、原文与 route 临时验证通过；最新引用卡片视觉与横屏专项仍待 Chrome 重新连接。2026-09-10 21:08 当前仅能发现应用内浏览器，Chrome 不可用；不将此前竖屏截图外推为本轮横屏通过。
- 真实重新提取 run `fb6632e225bd47aa8bd5a0b6903eaf11` 返回 202，最终 success，2 文件/7 页/5 文本页，6 个索引重新达到 indexed，当前无该样本运行中任务。媒体 manifest 已验证不包含 document_text 内部来源元数据。
- 内容 19 的删除在执行前被自动审批拒绝，要求用户明确授权永久清理样本、附件和索引。已发出确认，内容 19 与资产 49/50 完整保留；不得通过其他路径删除。临时引用验证脚本已移除，其他 PDF 样本与依赖实验环境仍保留待收尾。
- PDF 摘要已改为读取校验后的原生页，区分保存说明与来源正文；部分覆盖固定显示警示，尚未提取或没有可读页返回 409。自动摘要调整到提取之后并遵循既有开关。代码与隔离回归通过，真实摘要模型已对自制/公共内容 19 验收：正确涉及两份 PDF 的原页内容并标注覆盖限制，不能声称扫描页已被理解。
- 复杂版面、表格语义、扫描 OCR、Office 文档、原页预览与超大文档分页加载仍未实现。
- 页码关键词召回使用 SQLite JSON 条件过滤；没有独立页级 FTS 表，不宣称大规模搜索性能已验收。

## 样本来源

[pypdf 公共样本仓库](https://github.com/py-pdf/sample-files)，CC-BY-SA-4.0：`026-latex-multicolumn/multicolumn.pdf` 与 `005-libreoffice-writer-password/libreoffice-writer-password.pdf`。

## 原生文件选择器的通用 MIME 修复

当前 file_selector_macos 源码创建 XFile 时不提供 MIME；项目 MultipartFile 因而采用 Dio 的 application/octet-stream 默认值。修复前使用同样的真实 multipart 报文上传 PDF，后端返回 media_type=other、documents=0，跳过提取。后端现将通用二进制 MIME 与缺省 MIME 一样按文件名推断类型；明确 MIME 不改写，后续 PDF 提取仍校验文件头和 checksum。隔离 SQLite 中重新走正式上传、后台子进程和读取 API，结果为 document、1 份文档、空白 PDF 的真实 no_text 状态。没有修改用户数据库中的样本或现有内容；原生 macOS 文件选择器交互仍未实测。

## 真实 PDF 摘要与 Agent 页码回答（2026-09-10 21:35）

仅使用本次自制及公共样本内容 19，不发送私人收藏。正式 generate-summary 接口 HTTP 200，run `5fc48225cd57402bbf20daed95db3b59`：摘要包含第一份档案/分页样本及第二份多栏 Lorem Ipsum/欧盟国家信息表，固定保留部分页面未读取提示；保存说明不变、7 个原生页切片保留。

正式 Agent 接口 HTTP 200，run `run_8196945a3be64026b437ee61ec8bf575`、session `sess_ac2d21258d2d412a947eb8c66df27712`。问题只要求读取内容 19、资产 49、第 2 页的测试价格。实际回答：“该页写的测试金额是 128 元（并注明不是用户真实账单），见 native-text-sample.pdf 第2页”，链接为 `/collection/19?document_asset=49&page=2`。数据库确认 completed、回答已持久化，恰好一次 completed 的 read_content，参数匹配指定文件和页码，没有检索或读取其他收藏。

此证据覆盖一个已知页的真实模型读取、回答与引用，不代表开放式搜索、多文档综合、扫描页识别或全部回答质量通过。前端本次未重新完成视觉验收；样本及会话保留。
