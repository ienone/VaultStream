# UI-01：分发队列计划时间缺少日期

## 状态

active · P2 · 2026-09-13 UI 审校确认，尚未实施。

## 现象与证据

在分发队列安排非当天任务后，时间块仅显示时分，无法从列表判断它属于今天、明天或更晚。隔离样例安排在约十天后，实际页面显示 `23:47`。桌面与手机均可见该时间表达。

- [真实对照截图，图组 18](../knowledges/ui-review-2026-09-13/assets/18-comparison.png)
- [完整审校报告](../knowledges/ui-review-2026-09-13/README.md)
- [queue_content_list.dart](../../frontend/lib/features/automation/widgets/queue_content_list.dart)：`_buildTimeSection` 755 行附近将 `scheduledTime.toLocal()` 格式化为 `DateFormat('HH:mm')`；菜单 tooltip 只有“调整时间”。

本次未触发发送。问题是显示信息不足，不是已证明调度时间计算错误。

## 影响范围与期望

影响跨日排期的判断及调整。建议今天显示时间，非当天至少补充日期；tooltip 与无障碍名称提供完整本地日期时间。保持现有时区转换和调度行为，不引入第二套时间推算规则。

## 验证方式

使用同一天时刻、明天相同时刻、更远日期、空计划时间四类隔离数据，在桌面和手机列表检查可辨识性；另检查跨年与本地时区转换。调整时间后列表及时更新。验证只需临时 UI 验收，不需要真实发送消息。
