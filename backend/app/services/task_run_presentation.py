from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any


TASK_ERROR_STATUSES = frozenset({"error", "failed"})
TASK_SUCCESS_STATUSES = frozenset({"success", "completed", "ok"})
TASK_TERMINAL_STATUSES = TASK_ERROR_STATUSES | TASK_SUCCESS_STATUSES | {"cancelled"}

_TASK_TITLES = {
    "favorites_sync": "收藏同步",
    "content_parse": "内容解析",
    "content_reparse": "重新解析内容",
    "content_summary": "生成内容摘要",
    "content_embedding": "内容语义索引",
    "semantic_reindex": "重建语义索引",
    "discovery_sync": "发现源同步",
    "discovery_source_test": "发现源测试",
    "discovery_patrol": "动态候选评分",
    "distribution_push": "内容分发",
    "distribution_schedule": "调整分发队列",
    "distribution_worker_poll": "分发队列处理",
    "distribution_target_test": "分发目标连接测试",
    "distribution_target_send_test": "分发目标发送测试",
    "platform_parse_test": "平台解析测试",
    "ai_connectivity_test": "AI 连通性测试",
    "bot_chats_sync": "Bot 群组同步",
    "bot_runtime_control": "Telegram Bot 服务控制",
}


def build_task_run_presentation(run: Mapping[str, Any]) -> dict[str, Any]:
    """Project one persisted run into a stable, user-facing result contract."""
    task = _text(run.get("task")) or "unknown"
    status = _text(run.get("status")) or "unknown"
    metadata = _mapping(run.get("metadata"))
    result = _mapping(run.get("result"))
    title = _TASK_TITLES.get(task, _humanize_task(task))
    kind = _task_kind(task)

    sections = _sections_for_task(task, metadata, result)
    links = _entity_links(task, metadata, result)
    actions = _allowed_actions(task, status, metadata, result, links)
    error_code = _first_text(
        result.get("error_code"),
        result.get("reason"),
        result.get("error_type"),
    )

    return {
        "kind": kind,
        "title": title,
        "summary": _summary_for_task(
            task,
            status,
            title,
            _text(run.get("error")),
            metadata,
            result,
        ),
        "error_code": error_code,
        "entity_links": links,
        "allowed_actions": actions,
        "result_sections": sections,
    }


def _summary_for_task(
    task: str,
    status: str,
    title: str,
    error: str | None,
    metadata: Mapping[str, Any],
    result: Mapping[str, Any],
) -> str:
    if status == "running":
        return f"{title}正在运行。"
    if status in TASK_ERROR_STATUSES:
        return f"{title}未完成：{error}" if error else f"{title}未完成。"

    if task == "favorites_sync":
        totals = _favorites_totals(result)
        if totals["imported"] or totals["skipped"] or totals["failed"]:
            return (
                f"已导入 {totals['imported']} 条，跳过 {totals['skipped']} 条，"
                f"失败 {totals['failed']} 条。"
            )
        platform_count = _int(result.get("platform_count"))
        return f"已检查 {platform_count} 个平台，没有需要导入的新内容。"
    if task == "content_parse":
        if result.get("skipped") is True:
            reason = _text(result.get("reason"))
            return f"内容无需重复解析{f'：{reason}' if reason else '。'}"
        return "内容解析与后处理已完成。"
    if task == "content_reparse":
        return "内容已重新解析，可查看最新正文和解析候选。"
    if task == "content_summary":
        return "内容摘要已生成。" if result.get("summary_present") else "摘要任务已完成，但没有生成摘要。"
    if task == "content_embedding":
        return "内容已加入语义索引。" if result.get("indexed") else "语义索引任务已完成，但没有写入索引。"
    if task == "semantic_reindex":
        return (
            f"已索引 {_int(result.get('indexed'))} 个分块，"
            f"失败 {_int(result.get('failed'))} 个。"
        )
    if task == "discovery_sync":
        return f"已收录 {_int(result.get('ingested_count'))} 条新候选。"
    if task == "discovery_source_test":
        return f"已读取 {_int(result.get('item_count'))} 条候选用于连接验证。"
    if task == "discovery_patrol":
        return (
            f"已为 {_int(result.get('scored_count'))}/"
            f"{_int(result.get('candidate_count') or metadata.get('candidate_count'))} 条候选完成评分。"
        )
    if task == "distribution_push":
        return "内容已经发送到目标。"
    if task == "distribution_schedule":
        return f"已调整 {_int(result.get('changed'))} 个分发队列项。"
    if task == "distribution_worker_poll":
        return (
            f"本轮处理 {_int(result.get('claimed_count'))} 个队列项，"
            f"成功 {_int(result.get('success_count'))} 个，失败 {_int(result.get('failed_count'))} 个。"
        )
    if task in {"distribution_target_test", "distribution_target_send_test"}:
        return _text(result.get("message")) or f"{title}已完成。"
    if task == "platform_parse_test":
        parsed_title = _text(result.get("title"))
        return f"解析成功：{parsed_title}" if parsed_title else "平台页面解析测试已完成。"
    if task == "ai_connectivity_test":
        return f"{title}通过，耗时 {_number_text(result.get('elapsed_ms'))} ms。"
    if task == "bot_chats_sync":
        return (
            f"已检查 {_int(result.get('total'))} 个群组，"
            f"更新 {_int(result.get('updated'))} 个，失败 {_int(result.get('failed'))} 个。"
        )
    if task == "bot_runtime_control":
        runtime = _mapping(result.get("runtime"))
        runtime_status = _text(runtime.get("status")) or status
        return f"Telegram Bot 服务控制结果：{runtime_status}。"
    return f"{title}已完成。" if status in TASK_SUCCESS_STATUSES else f"{title}状态：{status}。"


def _sections_for_task(
    task: str,
    metadata: Mapping[str, Any],
    result: Mapping[str, Any],
) -> list[dict[str, Any]]:
    if task == "favorites_sync":
        totals = _favorites_totals(result)
        sections = [
            _section(
                "同步结果",
                [
                    _item("拉取", totals["fetched"]),
                    _item("导入", totals["imported"], "positive"),
                    _item("跳过", totals["skipped"]),
                    _item("失败", totals["failed"], "negative" if totals["failed"] else "neutral"),
                ],
            )
        ]
        if not any(totals.values()):
            sections = []
        platform_rows = _favorites_platform_rows(result)
        if platform_rows:
            sections.append(_section("平台明细", platform_rows))
        return sections

    if task in {"content_parse", "content_reparse", "content_summary", "content_embedding"}:
        items = [_item("内容 ID", _first_value(result.get("content_id"), metadata.get("content_id")))]
        if task == "content_parse":
            items.extend(
                [
                    _item("解析状态", result.get("status") or ("已跳过" if result.get("skipped") else "已完成")),
                    _item("尝试次数", result.get("attempt") or metadata.get("attempt")),
                    _item("原因", result.get("reason")),
                ]
            )
        elif task == "content_summary":
            items.extend(
                [
                    _item("摘要", "已生成" if result.get("summary_present") else "未生成"),
                    _item("内容分块", result.get("chunk_count")),
                    _item("标签", result.get("tag_count")),
                ]
            )
        elif task == "content_embedding":
            items.append(_item("语义索引", "已写入" if result.get("indexed") else "未写入"))
        return [_section("内容处理结果", items)]

    if task == "semantic_reindex":
        return [
            _section(
                "索引结果",
                [
                    _item("候选", _first_value(result.get("candidate_count"), metadata.get("candidate_count"))),
                    _item("已索引", result.get("indexed"), "positive"),
                    _item("已跳过", result.get("skipped")),
                    _item("失败", result.get("failed"), "negative" if _int(result.get("failed")) else "neutral"),
                ],
            )
        ]

    if task in {"discovery_sync", "discovery_source_test", "discovery_patrol"}:
        if task == "discovery_sync":
            items = [
                _item("来源", _first_text(result.get("source_name"), metadata.get("source_name"))),
                _item("新增候选", result.get("ingested_count"), "positive"),
                _item("来源类型", _first_text(result.get("source_kind"), metadata.get("source_kind"))),
            ]
        elif task == "discovery_source_test":
            items = [
                _item("来源", _first_text(result.get("source_name"), metadata.get("source_name"))),
                _item("读取候选", result.get("item_count"), "positive"),
                _item("样本", result.get("sample_count")),
                _item("耗时", _duration(result.get("elapsed_ms"))),
            ]
        else:
            items = [
                _item("候选", _first_value(result.get("candidate_count"), metadata.get("candidate_count"))),
                _item("已评分", result.get("scored_count"), "positive"),
                _item("失败", result.get("failed_count"), "negative" if _int(result.get("failed_count")) else "neutral"),
            ]
        return [_section("探索结果", items)]

    if task.startswith("distribution_"):
        items = [
            _item("目标平台", _first_text(result.get("target_platform"), result.get("platform"), metadata.get("target_platform"), metadata.get("platform"))),
            _item("目标", _first_text(result.get("target_id"), metadata.get("target_id"))),
        ]
        if task == "distribution_push":
            items.extend([_item("消息 ID", result.get("message_id")), _item("尝试次数", result.get("attempt_count"))])
        elif task == "distribution_schedule":
            items.extend([_item("调整队列项", result.get("changed"), "positive"), _item("动作", result.get("action") or metadata.get("action"))])
        elif task == "distribution_worker_poll":
            items.extend(
                [
                    _item("领取", result.get("claimed_count")),
                    _item("成功", result.get("success_count"), "positive"),
                    _item("失败", result.get("failed_count"), "negative" if _int(result.get("failed_count")) else "neutral"),
                ]
            )
        else:
            items.extend([_item("结果", result.get("message")), _item("耗时", _duration(result.get("elapsed_ms")))])
        return [_section("分发结果", items)]

    if task == "platform_parse_test":
        return [
            _section(
                "解析结果",
                [
                    _item("标题", result.get("title")),
                    _item("作者", result.get("author_name")),
                    _item("内容类型", result.get("content_type")),
                    _item("布局", result.get("layout_type")),
                    _item("正文长度", result.get("content_length")),
                    _item("媒体", _collection_count(result.get("media"))),
                    _item("耗时", _duration(result.get("elapsed_ms"))),
                ],
            )
        ]

    if task == "ai_connectivity_test":
        return [
            _section(
                "连通性",
                [
                    _item("能力", result.get("target") or metadata.get("target")),
                    _item("响应", "已收到" if result.get("response_present") else "未收到"),
                    _item("耗时", _duration(result.get("elapsed_ms"))),
                ],
            )
        ]

    if task == "bot_chats_sync":
        return [
            _section(
                "群组同步结果",
                [
                    _item("群组", result.get("total")),
                    _item("已更新", result.get("updated"), "positive"),
                    _item("不可访问", result.get("inaccessible"), "negative" if _int(result.get("inaccessible")) else "neutral"),
                    _item("失败", result.get("failed"), "negative" if _int(result.get("failed")) else "neutral"),
                ],
            )
        ]
    if task == "bot_runtime_control":
        runtime = _mapping(result.get("runtime"))
        return [
            _section(
                "服务控制结果",
                [
                    _item("动作", result.get("action") or metadata.get("action")),
                    _item("状态", runtime.get("status")),
                    _item("进程 ID", runtime.get("pid")),
                    _item("原因", result.get("reason") or metadata.get("reason")),
                ],
            )
        ]
    return []


def _entity_links(
    task: str,
    metadata: Mapping[str, Any],
    result: Mapping[str, Any],
) -> list[dict[str, str]]:
    links: list[dict[str, str]] = []
    content_id = _positive_int(_first_value(result.get("content_id"), metadata.get("content_id")))
    if content_id is not None:
        links.append({"kind": "content", "label": f"内容 #{content_id}", "href": f"/collection/{content_id}"})

    source_id = _positive_int(_first_value(result.get("source_id"), metadata.get("source_id")))
    if source_id is not None:
        links.append({"kind": "discovery_source", "label": f"发现源 #{source_id}", "href": "/automation/processing"})

    queue_item_id = _positive_int(_first_value(result.get("queue_item_id"), metadata.get("queue_item_id")))
    if queue_item_id is not None:
        links.append({"kind": "queue_item", "label": f"队列项 #{queue_item_id}", "href": "/automation/distribution"})

    if task == "favorites_sync":
        scope = _first_text(result.get("platform"), metadata.get("platform"), metadata.get("scope"))
        if scope and scope != "all":
            links.append({"kind": "account", "label": scope, "href": "/accounts"})
    return _dedupe_links(links)


def _allowed_actions(
    task: str,
    status: str,
    metadata: Mapping[str, Any],
    result: Mapping[str, Any],
    links: list[dict[str, str]],
) -> list[dict[str, str]]:
    actions: list[dict[str, str]] = []
    content_link = next((link for link in links if link["kind"] == "content"), None)
    if content_link:
        actions.append({"id": "open_content", "label": "查看内容", "href": content_link["href"], "emphasis": "primary"})

    if task == "favorites_sync":
        actions.append({"id": "open_sync", "label": "查看收藏同步", "href": "/automation/sync", "emphasis": "primary" if not actions else "secondary"})
        if status in TASK_ERROR_STATUSES:
            actions.append({"id": "open_accounts", "label": "检查账号", "href": "/accounts", "emphasis": "secondary"})
    elif task.startswith("distribution_"):
        actions.append({"id": "open_distribution", "label": "查看分发", "href": "/automation/distribution", "emphasis": "primary" if not actions else "secondary"})
    elif task.startswith("discovery_"):
        actions.append({"id": "open_feed", "label": "查看动态", "href": "/home", "emphasis": "primary" if not actions else "secondary"})
        actions.append({"id": "open_processing", "label": "查看自动化", "href": "/automation/processing", "emphasis": "secondary"})
    elif task in {"content_parse", "content_reparse", "content_summary", "content_embedding", "semantic_reindex"}:
        actions.append({"id": "open_processing", "label": "查看处理状态", "href": "/automation/processing", "emphasis": "secondary"})
    elif task == "ai_connectivity_test":
        actions.append({"id": "open_ai_settings", "label": "查看 AI 设置", "href": "/settings?tab=automation", "emphasis": "primary"})
    elif task in {
        "platform_parse_test",
        "bot_chats_sync",
        "bot_runtime_control",
    }:
        actions.append({"id": "open_accounts", "label": "查看账号中心", "href": "/accounts", "emphasis": "primary"})
    return _dedupe_actions(actions)


def _task_kind(task: str) -> str:
    if task == "favorites_sync":
        return "favorites_sync"
    if task in {"content_parse", "content_reparse", "content_summary", "content_embedding"}:
        return "content_processing"
    if task == "semantic_reindex":
        return "semantic_index"
    if task.startswith("discovery_"):
        return "discovery"
    if task.startswith("distribution_"):
        return "distribution"
    if task in {"platform_parse_test", "ai_connectivity_test"}:
        return "connectivity_test"
    if task == "bot_chats_sync":
        return "account_sync"
    if task == "bot_runtime_control":
        return "account_control"
    return "generic"


def _favorites_totals(result: Mapping[str, Any]) -> dict[str, int]:
    platform_results = _mapping(result.get("results"))
    if platform_results:
        rows = [_mapping(value) for value in platform_results.values()]
    else:
        nested = _mapping(result.get("result"))
        rows = [nested or result]
    return {
        "fetched": sum(_int(row.get("fetched")) for row in rows),
        "imported": sum(_int(row.get("imported")) for row in rows),
        "skipped": sum(_int(row.get("skipped")) for row in rows),
        "failed": sum(_int(row.get("failed_items_total") or row.get("failed")) for row in rows),
    }


def _favorites_platform_rows(result: Mapping[str, Any]) -> list[dict[str, str]]:
    platform_results = _mapping(result.get("results"))
    rows: list[dict[str, str]] = []
    for platform, raw in platform_results.items():
        item = _mapping(raw)
        status = _text(item.get("status")) or "unknown"
        summary = (
            f"拉取 {_int(item.get('fetched'))} · 导入 {_int(item.get('imported'))} · "
            f"跳过 {_int(item.get('skipped'))} · 失败 "
            f"{_int(item.get('failed_items_total') or item.get('failed'))}"
        )
        rows.append(_item(str(platform), summary, "negative" if status == "failed" else "positive" if status == "success" else "neutral"))
    return rows


def _section(title: str, items: Iterable[dict[str, str]]) -> dict[str, Any]:
    visible = [item for item in items if item.get("value") not in {"", "-", "None"}]
    return {"title": title, "items": visible}


def _item(label: str, value: Any, tone: str = "neutral") -> dict[str, str]:
    return {"label": label, "value": _display_value(value), "tone": tone}


def _mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _first_text(*values: Any) -> str | None:
    for value in values:
        text = _text(value)
        if text:
            return text
    return None


def _first_value(*values: Any) -> Any:
    for value in values:
        if value is not None and value != "":
            return value
    return None


def _int(value: Any) -> int:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    try:
        return int(str(value))
    except (TypeError, ValueError):
        return 0


def _positive_int(value: Any) -> int | None:
    parsed = _int(value)
    return parsed if parsed > 0 else None


def _duration(value: Any) -> str:
    return f"{_number_text(value)} ms" if value is not None else "-"


def _number_text(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.2f}".rstrip("0").rstrip(".")
    return str(value if value is not None else 0)


def _display_value(value: Any) -> str:
    if value is None:
        return "-"
    if isinstance(value, bool):
        return "是" if value else "否"
    if isinstance(value, (list, tuple, set)):
        return "、".join(str(item) for item in value) if value else "0"
    return str(value)


def _collection_count(value: Any) -> int:
    return len(value) if isinstance(value, (list, tuple, set, Mapping)) else 0


def _humanize_task(task: str) -> str:
    return task.replace("_", " ").strip().title() or "后台任务"


def _dedupe_links(links: list[dict[str, str]]) -> list[dict[str, str]]:
    seen: set[tuple[str, str]] = set()
    result: list[dict[str, str]] = []
    for link in links:
        key = (link["kind"], link["href"])
        if key not in seen:
            seen.add(key)
            result.append(link)
    return result


def _dedupe_actions(actions: list[dict[str, str]]) -> list[dict[str, str]]:
    seen: set[tuple[str, str]] = set()
    result: list[dict[str, str]] = []
    for action in actions:
        key = (action["id"], action["href"])
        if key not in seen:
            seen.add(key)
            result.append(action)
    return result
