# 当前问题

本目录记录尚需处理的问题，具体状态与证据见各文档。旧审计中的问题应结合当前代码重新核验，不能直接当作本版本事实。

- [交互问题](2026-09-07-interaction-failures.md)
- [真实场景验收与剩余边界](2026-09-10-real-world-acceptance.md)
- [分发队列日期显示](2026-09-13-ui-queue-date.md)
- [持续处理接续与事件证据保留](2026-09-14-continuous-processing-integrity.md)：P0 的解析/分发租约、未知结果核对与 TTL 保护已本地修复；继续跟踪耐久后处理、稳定证据版本和主动擦除边界。
- [后端 CI 环境可复现性](backend-ci-environment-reproducibility.md)
- [图片归档与缓存残留问题](2026-09-19-media-localization-integrity.md)：归档主链已收敛；剩余自动补齐触发与客户端缓存身份。
- [仓库审计](repository-audit.md)

已关闭问题的关键取舍收拢到[历史决策](archive/README.md)。普通修复日志和旧截图不逐个归档；当前实现回到对应模块维护。问题记录说明现象、影响、处理方向和必要证据即可，不要求机械填写模板。
