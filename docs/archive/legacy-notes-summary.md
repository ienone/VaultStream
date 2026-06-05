# 旧审计与问题记录摘要

> 来源：旧 `audits/`、`known-issues/` 和零散历史记录。  
> 当前状态：只保留仍有参考价值的结论。

## 代码审计统计

旧 `code_audit_report_20260324.md` 记录过一次仓库规模和重复度扫描。它的价值是说明项目复杂度已经超过原型阶段：

- 后端、前端、测试和文档均已有较大体量。
- 大文件和生成文件曾显著影响 LOC 统计。
- `frontend/lib/features/settings/presentation/tabs/automation_tab.dart`、review 相关 widget、平台 adapter 等曾是复杂度集中点。

这些数字是历史快照，不再作为当前规模依据。

## 配置流审计

旧配置审计指出过 Onboarding、Settings、system settings、local settings、API client 之间的路径和职责漂移。

当前仍有参考价值的结论：

- 用户不应直接面对过多模型和 key 的低层配置。
- 配置应按能力展示：内容理解、摘要、语义搜索、Agent、推送。
- 前端本地连接设置和后端系统设置需要清晰分层。

## 测试进度记录

旧测试进度文档记录过后端覆盖率提升过程。已完成的覆盖率里程碑不再保留为当前状态。

当前应关注：

- 非 integration 测试通过不等于真实平台链路通过。
- integration 测试需要固定 cwd、DB_PATH、外部服务配置和登录态边界。
- Flutter widget 测试通过后仍需补关键用户路径的视觉/交互验收。

## 已归档问题

旧 `discovery.md` 和 `flutter-ufffd-utf8-bug.md` 是历史问题线索。

当前保留的判断：

- Discovery 仍有当前已知 UI 问题，见 `docs/known-issues/discovery-detail-top-overlap.md`。
- 编码问题排查时应先确认读取工具和终端编码；不要把 PowerShell 默认编码显示问题误判为文件损坏。

## 历史修复记录处理原则

已确认完成的历史修复不再保留原文。若以后需要追溯，可从 git 历史查看旧文件；当前 docs 只保留仍影响路线图、风险判断或验收计划的内容。
