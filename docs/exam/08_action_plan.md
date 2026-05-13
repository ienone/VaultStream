# 分级整改计划

## P0：先恢复交付可信度

1. 修复后端 pytest 收集失败  
   - 同步 `backend/tests/test_content_summary.py` 与当前 `content_summary_service.py`。
   - 决定是恢复 `generate_summary_llm` 兼容函数，还是重写测试指向新接口。
   - 验证：`.venv\Scripts\python.exe -m pytest backend/tests -q`。

2. 关闭前端默认敏感日志  
   - `DEBUG_LOG` 默认改为 false。
   - Dio LogInterceptor redacts `X-API-Token`、`Authorization`、cookie、bot token。
   - release workflow 显式传 `--dart-define=DEBUG_LOG=false`。

## P1：安全与核心功能

3. 升级 `lxml`  
   - 升到 `>=6.1.0`。
   - 检查 parser 调用是否处理不可信 XML。
   - 验证 adapter/parser 测试。

4. 修复图片代理 SSRF 与大文件风险  
   - debug 不再全量跳过内网 IP 校验。
   - redirect 后重验最终地址。
   - 增加 Content-Length、累计读取、像素尺寸限制。
   - 考虑 token/signature 或 origin 限制。

5. 补齐 FTS migration  
   - 创建 `contents_fts`、trigger、backfill。
   - search health 暴露 FTS 状态。
   - `text_search.py` 不再静默吞掉缺表问题。

6. 固化 Flutter 验证口径  
   - 在 `frontend` 目录顺序执行 `flutter analyze` 与 `flutter test`。
   - 生成文件不提交时，CI/新环境先跑 build_runner。
   - 测试日志应避免打印敏感 header。

7. 统一外部 URL 打开  
   - 所有 `launchUrl(Uri.parse(...))` 改走 `safe_url_launcher.dart`。
   - 测试 http/https、非法 scheme、空 URL。

8. 统一 adapter 生命周期  
   - 为 adapter 增加 async context manager 或统一 close helper。
   - parsing/create_share 等路径 finally 关闭。

## P2：架构和性能收敛

9. 建立 post-ingest pipeline  
   - parse/discovery/favorites 都进入同一 hook。
   - hook 负责 summary、embedding、patrol、distribution。

10. 收敛分发决策入口  
   - `engine.py`、`scheduler.py`、`tasks/parsing.py` 只保留一个 service 作为业务入口。
   - 增加规则行为回归测试。

11. 改进语义检索性能  
   - 记录候选数和查询耗时。
   - 限制候选范围。
   - 评估 sqlite-vec/sqlite-vss 或独立向量索引。

12. 给 Agent 和 Bot 前端补 typed DTO  
   - Agent result sealed union。
   - Bot config model。
   - 后端 response schema 对齐。

13. 修正文档漂移  
   - 用 OpenAPI 自动生成 endpoint 清单。
   - 更新 `docs/API.md`、`docs/DATABASE.md`、`docs/architecture/BACKEND.md`。

14. CI 加质量门禁  
   - PR：pytest、build_runner、flutter analyze、flutter test。
   - Release：pip-audit、bandit、Docker scan、debug flag check。

15. 补齐健康检查与后台任务诊断
   - `/health` 暴露 DB、FTS、worker、provider 配置状态。
   - 后台任务记录 last_success_at、last_error_at、pending/failed/retry count。
   - 搜索降级、embedding 失败、分发失败写结构化日志。

## P3：清理与体验

16. 清理 vulture 候选  
   - 先人工确认 pytest fixture 与动态 import。
   - 小批量删除未使用 import/变量。

17. 明确图片缓存库边界  
   - 列表缩略图：cached_network_image。
   - 全屏/手势：extended_image。
   - 统一 placeholder/error UI。

18. 字体策略  
   - 打包 Google Fonts 字体资产，或禁用 runtime fetching。
   - 验证离线/内网首屏。

19. Docker 运行用户  
   - 后端镜像改非 root。
   - 增加 healthcheck 与镜像扫描。

## 推荐执行批次

### Batch 1：质量门禁恢复

- P0-1 pytest
- P0-2 debug log
- P1-6 Flutter 验证口径与日志

### Batch 2：安全修复

- P1-3 lxml
- P1-4 image proxy
- P1-7 safe URL launcher

### Batch 3：搜索/RAG 数据闭环

- P1-5 FTS
- P2-9 post-ingest
- P2-11 vector search

### Batch 4：工程收敛

- P2-10 distribution
- P2-12 typed DTO
- P2-13 docs
- P2-14 CI
- P2-15 observability
