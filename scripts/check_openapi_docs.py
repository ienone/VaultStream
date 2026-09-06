"""Check that the generated endpoint document matches the current FastAPI OpenAPI."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from unittest.mock import patch


ENDPOINT_ROW = re.compile(r"^\|\s*`(?P<methods>[^`]+)`\s*\|\s*`(?P<path>[^`]+)`\s*\|")

REQUIRED_ACTION_RESPONSE_MODELS = {
    (
        "delete",
        "/api/v1/pushed-records/{record_id}",
        "200",
    ): "PushedRecordDeleteResponse",
    (
        "post",
        "/api/v1/cards/{card_id}/review",
        "200",
    ): "CardReviewResponse",
    (
        "post",
        "/api/v1/cards/batch-review",
        "200",
    ): "BatchCardReviewResponse",
    (
        "delete",
        "/api/v1/distribution-rules/{rule_id}",
        "200",
    ): "DistributionRuleDeleteResponse",
    (
        "post",
        "/api/v1/distribution/trigger-run",
        "200",
    ): "DistributionTriggerResponse",
    (
        "delete",
        "/api/v1/settings/{key}",
        "200",
    ): "SystemSettingDeleteResponse",
    (
        "delete",
        "/api/v1/bot/chats/{bot_chat_id}",
        "200",
    ): "BotChatDeleteResponse",
    (
        "post",
        "/api/v1/bot/chats/{bot_chat_id}/toggle",
        "200",
    ): "BotChatToggleResponse",
    (
        "post",
        "/api/v1/bot/heartbeat",
        "200",
    ): "BotHeartbeatResponse",
    (
        "delete",
        "/api/v1/contents/{content_id}/media-bookmarks/{bookmark_id}",
        "200",
    ): "MediaBookmarkDeleteResponse",
    (
        "delete",
        "/api/v1/knowledge-events/{event_id}/members/{content_id}",
        "200",
    ): "KnowledgeEventMemberRemoveResponse",
    (
        "post",
        "/api/v1/search/semantic/embeddings/{embedding_id}/retry",
        "200",
    ): "SemanticEmbeddingRetryResponse",
    (
        "delete",
        "/api/v1/agent/sessions/{session_id}",
        "200",
    ): "AgentSessionActionResponse",
    (
        "post",
        "/api/v1/agent/sessions/{session_id}/clear",
        "200",
    ): "AgentSessionActionResponse",
    (
        "delete",
        "/api/v1/contents/{content_id}",
        "200",
    ): "ContentDeleteResponse",
    (
        "post",
        "/api/v1/contents/{content_id}/retry",
        "200",
    ): "ContentRetryResponse",
    (
        "post",
        "/api/v1/contents/{content_id}/generate-summary",
        "200",
    ): "ContentSummaryActionResponse",
    (
        "post",
        "/api/v1/contents/{content_id}/patrol-score",
        "200",
    ): "ContentPatrolScoreResponse",
    (
        "post",
        "/api/v1/contents/{content_id}/re-parse",
        "200",
    ): "ContentReparseAcceptedResponse",
    (
        "post",
        "/api/v1/bot-config",
        "201",
    ): "BotConfigMutationResponse",
    (
        "patch",
        "/api/v1/bot-config/{config_id}",
        "200",
    ): "BotConfigMutationResponse",
    (
        "post",
        "/api/v1/bot-config/{config_id}/activate",
        "200",
    ): "BotConfigMutationResponse",
    (
        "delete",
        "/api/v1/bot-config/{config_id}",
        "200",
    ): "BotConfigDeleteResponse",
    (
        "delete",
        "/api/v1/browser-auth/session/{session_id}",
        "200",
    ): "AuthActionResponse",
    (
        "post",
        "/api/v1/browser-auth/{platform}/logout",
        "200",
    ): "AuthActionResponse",
    (
        "delete",
        "/api/v1/browser-auth/{platform}",
        "200",
    ): "AuthActionResponse",
    (
        "post",
        "/api/v1/browser-auth/zhihu/refresh-zse",
        "200",
    ): "AuthActionResponse",
    (
        "post",
        "/api/v1/bot-config/service/telegram/start",
        "200",
    ): "BotRuntimeActionResponse",
    (
        "post",
        "/api/v1/bot-config/service/telegram/stop",
        "200",
    ): "BotRuntimeActionResponse",
    (
        "post",
        "/api/v1/bot-config/service/telegram/restart",
        "200",
    ): "BotRuntimeActionResponse",
    (
        "post",
        "/api/v1/bot-config/{config_id}/sync-chats",
        "200",
    ): "BotConfigSyncChatsResponse",
    ("post", "/api/v1/ai/connectivity-test", "200"): "AIConnectivityTestResponse",
    ("post", "/api/v1/ai/models", "200"): "AIModelDiscoveryResponse",
    ("post", "/api/v1/platform-health/parse-test", "200"): "PlatformParseTestResponse",
    ("post", "/api/v1/favorites-sync/sync", "202"): "FavoritesSyncAcceptedResponse",
    (
        "post",
        "/api/v1/favorites-sync/runs/{run_id}/retry",
        "202",
    ): "FavoritesSyncAcceptedResponse",
    ("post", "/api/v1/favorites-sync/items/retry", "200"): "FavoritesSyncItemRetryResponse",
    (
        "post",
        "/api/v1/favorites-sync/items/batch-retry",
        "200",
    ): "FavoritesSyncItemsRetryResponse",
    (
        "post",
        "/api/v1/discovery/sources/{source_id}/test",
        "200",
    ): "DiscoverySourceTestResponse",
    (
        "post",
        "/api/v1/discovery/sources/{source_id}/sync",
        "202",
    ): "DiscoverySyncAcceptedResponse",
    (
        "post",
        "/api/v1/discovery/items/bulk-action",
        "200",
    ): "DiscoveryBulkActionResponse",
    (
        "delete",
        "/api/v1/discovery/sources/{source_id}",
        "200",
    ): "DiscoverySourceDeleteResponse",
    (
        "post",
        "/api/v1/distribution-queue/enqueue/{content_id}",
        "200",
    ): "QueueEnqueueResponse",
    (
        "post",
        "/api/v1/distribution-queue/items/{item_id}/cancel",
        "200",
    ): "QueueCancelResponse",
    (
        "post",
        "/api/v1/distribution-queue/batch-retry",
        "200",
    ): "BatchQueueRetryResponse",
    (
        "post",
        "/api/v1/distribution-queue/items/batch-push-now",
        "200",
    ): "QueueChangedResponse",
    (
        "post",
        "/api/v1/distribution-queue/items/batch-schedule",
        "200",
    ): "QueueChangedResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/{content_id}/status",
        "200",
    ): "QueueMovedResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/{content_id}/repush-now",
        "200",
    ): "QueueRepushResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/batch-repush-now",
        "200",
    ): "QueueRepushResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/{content_id}/reorder",
        "200",
    ): "QueueChangedResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/{content_id}/push-now",
        "200",
    ): "QueueChangedResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/{content_id}/schedule",
        "200",
    ): "QueueChangedResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/batch-push-now",
        "200",
    ): "QueueChangedResponse",
    (
        "post",
        "/api/v1/distribution-queue/content/batch-reschedule",
        "200",
    ): "QueueChangedResponse",
}

REQUIRED_EMPTY_ACTION_RESPONSES = {
    (
        "delete",
        "/api/v1/distribution-rules/{rule_id}/targets/{target_id}",
        "204",
    ),
}


def _bootstrap_backend_path() -> Path:
    repo_root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(repo_root / "backend"))
    return repo_root


def _openapi_inventory() -> dict[str, str]:
    # Contract checks must not initialize a persistent runtime database.
    os.environ["SQLITE_DB_PATH"] = ":memory:"
    from app.core import logging as app_logging

    app_logging.logger.remove()
    with patch.object(app_logging, "setup_logging"):
        from app.main import app

    inventory: dict[str, str] = {}
    for path, methods in sorted(app.openapi()["paths"].items()):
        inventory[path] = ", ".join(
            sorted(method.upper() for method in methods if method.lower() != "parameters")
        )
    return inventory


def _docs_inventory(api_doc: Path) -> dict[str, str]:
    inventory: dict[str, str] = {}
    for line in api_doc.read_text(encoding="utf-8").splitlines():
        match = ENDPOINT_ROW.match(line.strip())
        if match:
            inventory[match.group("path")] = match.group("methods")
    return inventory


def _action_contract_mismatches() -> list[str]:
    from app.main import app

    paths = app.openapi()["paths"]
    mismatches: list[str] = []
    for (method, path, status), expected_model in REQUIRED_ACTION_RESPONSE_MODELS.items():
        try:
            schema = paths[path][method]["responses"][status]["content"][
                "application/json"
            ]["schema"]
        except KeyError:
            mismatches.append(
                f"{method.upper()} {path} {status}: missing JSON response schema"
            )
            continue
        expected_ref = f"#/components/schemas/{expected_model}"
        if schema.get("$ref") != expected_ref:
            mismatches.append(
                f"{method.upper()} {path} {status}: "
                f"expected={expected_ref} actual={schema}"
            )
    for method, path, status in REQUIRED_EMPTY_ACTION_RESPONSES:
        response = paths.get(path, {}).get(method, {}).get("responses", {}).get(status)
        if response is None:
            mismatches.append(f"{method.upper()} {path} {status}: missing response")
        elif response.get("content"):
            mismatches.append(
                f"{method.upper()} {path} {status}: expected no response body "
                f"actual={response['content']}"
            )
    return mismatches


def main() -> int:
    repo_root = _bootstrap_backend_path()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "api_doc",
        nargs="?",
        default=str(repo_root / "docs" / "backend" / "api" / "endpoints.md"),
        help="Path to the generated OpenAPI endpoint Markdown.",
    )
    args = parser.parse_args()

    api_doc = Path(args.api_doc)
    if not api_doc.is_absolute():
        api_doc = (Path.cwd() / api_doc).resolve()

    expected = _openapi_inventory()
    actual = _docs_inventory(api_doc)
    missing = sorted(set(expected) - set(actual))
    stale = sorted(set(actual) - set(expected))
    method_mismatch = sorted(
        path for path in set(expected) & set(actual) if expected[path] != actual[path]
    )
    contract_mismatches = _action_contract_mismatches()

    if not (missing or stale or method_mismatch or contract_mismatches):
        print(
            "OpenAPI docs check passed: "
            f"{len(expected)} endpoints covered, "
            f"{len(REQUIRED_ACTION_RESPONSE_MODELS) + len(REQUIRED_EMPTY_ACTION_RESPONSES)} "
            "action contracts verified."
        )
        return 0

    if missing:
        print(f"Missing endpoints in {api_doc}:")
        for path in missing:
            print(f"  | `{expected[path]}` | `{path}` |")
    if stale:
        print(f"Stale endpoints in {api_doc}:")
        for path in stale:
            print(f"  | `{actual[path]}` | `{path}` |")
    if method_mismatch:
        print(f"Method mismatches in {api_doc}:")
        for path in method_mismatch:
            print(f"  {path}: docs={actual[path]} openapi={expected[path]}")
    if contract_mismatches:
        print("Action response contract mismatches:")
        for mismatch in contract_mismatches:
            print(f"  {mismatch}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
