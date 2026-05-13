# 代码质量审计

## 当前阻断项

后端测试在收集阶段失败：

```text
ImportError: cannot import name 'generate_summary_llm' from 'app.services.content_summary_service'
```

触发文件：`backend/tests/test_content_summary.py:6`。这说明 summary service 的重构没有同步测试，是当前最直接的质量门禁阻断。

## 后端质量问题

### 1. 重构残留与重复入口

- `content_summary_service.py` 中存在重复的 Pydantic model 定义：`SemanticChunk`、`ContentIntelligence`。
- `DistributionService`、`distribution.scheduler`、`tasks.parsing` 都保留分发相关入口。
- `text_search.py` 捕获 FTS 查询异常并返回空列表，使缺失 FTS 表变成静默行为。

### 2. 静态死代码候选

`vulture backend\app backend\tests --min-confidence 80` 返回多处候选，包括：

- `backend/app/adapters/utils/tiered_fetcher.py` 未使用 import `anyio`。
- zhihu parser 中存在未使用 import/变量候选。
- `backend/app/core/db_adapter.py`、`backend/app/services/patrol_service.py` 有未使用变量候选。
- 测试中有多个 fixture/变量候选，需要区分 pytest fixture 与真正死代码。

这些不一定都应删除，但应作为清理清单逐项确认。

### 3. 类型过宽

- `backend/app/models/content.py` 多个字段使用 `Mapped[Any]` + JSON。
- `backend/app/models/search.py` 将 embedding 向量存为 JSON `Mapped[Any]`。
- `backend/app/routers/discovery.py` 使用 `response_model=dict`。

这会削弱 API 契约、测试生成和前端模型同步能力。

### 4. Adapter 生命周期不一致

`AdapterFactory.create()` 会实例化 adapter；`RssAdapter`、`TelegramAdapter` 内部持有 `httpx.AsyncClient` 并提供 `close()`，但 `tasks/parsing.py` 和 `ContentService.create_share` 等调用路径未统一在 finally 中关闭 adapter。高频解析时可能泄露连接池资源。

## 前端质量问题

### 1. Codegen 策略需固定

代码中存在 `part '*.g.dart'`、`@riverpod`、`@freezed`、`json_serializable` 使用；`frontend/.gitignore` 忽略了 `*.g.dart` 与 `*.freezed.dart`。当前工作区存在生成文件，且 `cd frontend && flutter analyze` 已通过。风险不再是“生成文件缺失”，而是需要明确：生成文件不提交时，所有本地/CI 验证必须先运行 codegen。

建议把本地验证流程固定为：

```powershell
cd frontend
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

是否提交 generated files 取决于项目策略，但策略需要明确。

### 2. 动态 Map 过多

典型位置：

- `frontend/lib/features/agent/agent_page.dart`：直接解析 tool result 的 raw map/list。
- `frontend/lib/features/bot/bot_management_page.dart`：`List<Map<String, dynamic>>` 存储和转换 bot config。

这类页面一旦后端字段变更，编译期无法发现。

### 3. URL 打开逻辑重复

已有 `frontend/lib/core/utils/safe_url_launcher.dart`，但多个 UI 组件仍直接使用 `launchUrl(Uri.parse(...))`。这既是安全问题，也是质量问题：错误处理、scheme allowlist、日志都无法统一。

### 4. 图片缓存库重复

`frontend/pubspec.yaml` 同时使用：

- `cached_network_image: ^3.4.1`
- `extended_image: ^8.2.0`

实际代码中列表/卡片多用 `CachedNetworkImage`，详情 gallery 使用 `ExtendedImage.network`。这可以成立，但需要明确边界：普通缩略图用 cached_network_image，手势/大图预览用 extended_image，否则缓存策略和错误态会持续分叉。

### 5. Google Fonts 运行时风险

`frontend/lib/theme/app_theme.dart` 和 markdown config 使用 `GoogleFonts.*`。如果没有显式禁用 runtime fetching 或打包字体，在离线/内网/隐私约束环境中会有不确定网络访问和首屏字体抖动风险。

## 推荐清理顺序

1. 修复 pytest 收集失败。
2. 固化 codegen -> analyze/test 的验证顺序，避免新环境缺生成文件。
3. 统一安全 URL launcher。
4. 给 Agent/Bot 页面补 typed DTO。
5. 清理 vulture 候选和重复 model。
6. 明确图片库与字体策略。
