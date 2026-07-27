# 后端模块：内容管理

## 文档状态

active

## 代码位置

- Router: `backend/app/routers/contents.py`
- Service: `backend/app/services/content_service.py`
- Presenter: `backend/app/services/content_presenter.py`
- Repository: `backend/app/repositories/content_repository.py`
- Model/Schema: `backend/app/models/content.py`、`backend/app/schemas/content.py`

## 功能

- 接收分享 URL 或手动内容。
- 调用平台适配器解析内容。
- 存储标题、正文、作者、媒体、统计、标签、状态和 archive metadata。
- 提供内容列表、详情、编辑、删除、重新解析和后处理状态。

## 不承担职责

- 不直接实现平台认证。
- 不直接执行推送分发。
- 不直接持有全局自动化策略；只读取策略结果。

## 实现逻辑

内容创建入口会规范化 URL，解析后写入 `contents`，并触发后处理：摘要、语义索引、媒体归档、分发队列刷新等。详情返回前会通过 presenter 转换 `local://` 媒体 URL，并补充有效布局类型。

平台解析器统一输出 `ParsedContent`，写入边界位于 `tasks/parsing.py`：

- 标题、正文、作者、封面、正文媒体、发布时间、平台 ID、原生类型和布局类型写入对应列。
- `view/like/favorite/share/reply` 映射到五个通用统计列；平台独有统计写入 `extra_stats`。
- 平台话题写入 `source_tags`；引用内容、投票等可展示结构写入 `rich_payload`；原始响应和归档处理输入写入私有 `archive_metadata`。
- 头像可以进入私有归档供本地化，但不得作为正文 `media_urls` 或无媒体内容的封面。
- 生产解析与 `/platform-health/parse-test` 共用 `services/platform_parsing.py` 创建适配器，均读取数据库中扫码登录保存的完整平台 Cookie；Bilibili 仅在数据库未配置时回退到旧环境变量分片。

## 测试

- `backend/tests/test_api/test_contents.py`
- `backend/tests/test_api/test_content_processing_status.py`
- `backend/tests/test_content_service_tags.py`
- `backend/tests/test_content_service_deep.py`
- `backend/tests/test_content_presenter.py`

## 与其他模块交互

- adapters: 解析平台内容。
- media: 提取、归档、转换图片和视频。
- search-rag: 写入语义索引。
- distribution: 入库后可进入分发队列。
- events/tasks: 发送内容变化和任务状态。

## 对应前端

- `../../frontend/pages/collection.md`
- `../../frontend/pages/content-detail.md`

## API 接口

详见 `../api.md` 中内容管理 API，包括 `/shares`、`/contents`、`/contents/{id}`、`/contents/{id}/re-parse` 等。

## 配置与策略

- 解析、摘要、语义索引、媒体归档和分发是否执行应受系统配置和自动化策略约束。
- 内容详情只暴露当前状态，不应绕过后端策略触发外部副作用。

## 当前问题

- 详情后处理面板副作用：`../../issues/frontend-post-processing-panel-side-effects.md`
- 统一任务结果 contract：`../../issues/task-run-result-contract-missing.md`
- 媒体代理与图片访问：`../../issues/media-proxy-image-access.md`

## 尚未实现 / 计划扩展

内容模板、任务结果和媒体体验分别属于系统构想与前端 IA 的目标能力；每个部分开始实施前都要重新核对当前数据模型、API、真实样本和相关 issue。
