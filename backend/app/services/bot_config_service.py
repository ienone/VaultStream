from __future__ import annotations

from collections.abc import Awaitable
from typing import Any, Callable

import httpx
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.core.config import settings
from app.core.db_adapter import AsyncSessionLocal
from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import BotChat, BotChatType, BotConfig, BotConfigPlatform
from app.schemas import (
    BotConfigCreate,
    BotConfigDeleteResponse,
    BotConfigMutationResponse,
    BotConfigQrCodeResponse,
    BotConfigResponse,
    BotConfigSyncChatsResponse,
    BotConfigUpdate,
)
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.bot_config_runtime import get_primary_bot_config
from app.services.settings_service import get_setting_value
from app.services.telegram_bot_service import (
    restart_telegram_bot,
    start_telegram_bot,
    stop_telegram_bot,
)
from app.services.telegram_sync import refresh_telegram_chats
from app.utils.sensitive_display import mask_token_partial


class BotConfigNotFoundError(LookupError):
    pass


class BotConfigValidationError(ValueError):
    pass


class TelegramBotRuntimeService:
    """Own Telegram process-control side effects outside the API router."""

    @staticmethod
    def _trigger_for_reason(reason: str) -> str:
        return (
            "manual"
            if reason.startswith("api_manual_")
            else "config_change"
        )

    @staticmethod
    def _runtime_error(result: dict[str, Any]) -> str | None:
        if str(result.get("status") or "").lower() == "error":
            return str(result.get("error") or "Bot runtime action failed")
        for stage in ("stopped", "started"):
            nested = result.get(stage)
            if not isinstance(nested, dict):
                continue
            if str(nested.get("status") or "").lower() == "error":
                return str(
                    nested.get("error")
                    or f"Bot runtime {stage} stage failed"
                )
        return None

    async def _execute(
        self,
        *,
        action: str,
        reason: str,
        operation: Callable[[], Awaitable[dict[str, Any]]],
    ) -> dict[str, Any]:
        run = await record_task_run_started(
            "bot_runtime_control",
            trigger=self._trigger_for_reason(reason),
            platform=BotConfigPlatform.TELEGRAM.value,
            action=action,
            reason=reason,
        )
        try:
            result = await operation()
        except Exception as exc:
            await record_task_run_error(
                "bot_runtime_control",
                run["run_id"],
                exc,
                action=action,
                reason=reason,
            )
            return {
                "status": "error",
                "error": str(exc),
                "run_id": run["run_id"],
            }

        runtime_result = dict(result)
        runtime_error = self._runtime_error(runtime_result)
        if runtime_error:
            runtime_result["status"] = "error"
            runtime_result["error"] = runtime_error
            await record_task_run_error(
                "bot_runtime_control",
                run["run_id"],
                runtime_error,
                action=action,
                reason=reason,
                runtime=runtime_result,
            )
        else:
            await record_task_run_success(
                "bot_runtime_control",
                run["run_id"],
                action=action,
                reason=reason,
                runtime=runtime_result,
            )
        return {**runtime_result, "run_id": run["run_id"]}

    async def sync_process(self, db: AsyncSession, *, reason: str) -> dict[str, Any]:
        async def operation() -> dict[str, Any]:
            cfg = await get_primary_bot_config(
                db,
                BotConfigPlatform.TELEGRAM,
                enabled_only=True,
            )
            if cfg and cfg.bot_token and cfg.bot_token.strip():
                api_token = await get_setting_value("api_token")
                if not api_token and settings.api_token:
                    api_token = settings.api_token.get_secret_value()
                return await run_in_threadpool(
                    restart_telegram_bot,
                    reason=reason,
                    api_token=str(api_token or ""),
                )
            return await run_in_threadpool(
                stop_telegram_bot,
                reason=f"{reason}:no_enabled_telegram",
            )

        return await self._execute(
            action="sync",
            reason=reason,
            operation=operation,
        )

    async def start(self, *, reason: str) -> dict[str, Any]:
        async def operation() -> dict[str, Any]:
            return await run_in_threadpool(start_telegram_bot, reason=reason)

        return await self._execute(
            action="start",
            reason=reason,
            operation=operation,
        )

    async def stop(self, *, reason: str) -> dict[str, Any]:
        async def operation() -> dict[str, Any]:
            return await run_in_threadpool(stop_telegram_bot, reason=reason)

        return await self._execute(
            action="stop",
            reason=reason,
            operation=operation,
        )


class BotChatSyncService:
    """Own external Bot discovery and chat persistence side effects."""

    def __init__(
        self,
        client_factory: Callable[..., httpx.AsyncClient] | None = None,
    ) -> None:
        self._client_factory = client_factory or httpx.AsyncClient

    async def schedule_auto_sync(
        self,
        config_id: int,
        add_task: Callable[..., Any],
    ) -> str:
        run = await record_task_run_started(
            "bot_chats_sync",
            trigger="automatic",
            bot_config_id=config_id,
            platform=BotConfigPlatform.QQ.value,
        )
        add_task(self.auto_sync_background, config_id, run["run_id"])
        return run["run_id"]

    async def auto_sync_background(
        self,
        config_id: int,
        run_id: str | None = None,
    ) -> None:
        try:
            async with AsyncSessionLocal() as db:
                cfg = await db.scalar(
                    select(BotConfig).where(BotConfig.id == config_id)
                )
                if not cfg or not cfg.enabled:
                    if run_id:
                        await record_task_run_success(
                            "bot_chats_sync",
                            run_id,
                            bot_config_id=config_id,
                            skipped=True,
                        )
                    return
                if cfg.platform != BotConfigPlatform.QQ or not cfg.napcat_http_url:
                    if run_id:
                        await record_task_run_error(
                            "bot_chats_sync",
                            run_id,
                            "QQ Bot config is no longer eligible for chat sync",
                            bot_config_id=config_id,
                        )
                    return
                await self.sync(
                    cfg,
                    db,
                    trigger="automatic",
                    run_id=run_id,
                )
        except Exception as exc:
            logger.warning("Auto-sync chats failed for config {}: {}", config_id, exc)

    async def get_qr_code(self, cfg: BotConfig) -> BotConfigQrCodeResponse:
        endpoint = cfg.napcat_http_url.rstrip("/") + "/get_qrcode"
        try:
            headers = {}
            if cfg.napcat_access_token:
                headers["Authorization"] = f"Bearer {cfg.napcat_access_token}"
            async with self._client_factory(timeout=10.0) as client:
                response = await client.get(endpoint, headers=headers)
                if response.status_code != 200:
                    return BotConfigQrCodeResponse(
                        bot_config_id=cfg.id,
                        status="error",
                        message=f"Napcat response status={response.status_code}",
                    )
                payload = response.json()
        except Exception as exc:
            return BotConfigQrCodeResponse(
                bot_config_id=cfg.id,
                status="error",
                message=f"Napcat request failed: {exc}",
            )

        data = payload.get("data") if isinstance(payload, dict) else None
        qr_code = None
        if isinstance(data, dict):
            qr_code = data.get("qr_code") or data.get("image") or data.get("url")
        return BotConfigQrCodeResponse(
            bot_config_id=cfg.id,
            status="ok" if qr_code else "pending",
            qr_code=qr_code,
            message="ok" if qr_code else "No qr_code in response",
        )

    async def sync(
        self,
        cfg: BotConfig,
        db: AsyncSession,
        *,
        trigger: str = "manual",
        run_id: str | None = None,
    ) -> BotConfigSyncChatsResponse:
        platform = cfg.platform.value
        if run_id is None:
            run = await record_task_run_started(
                "bot_chats_sync",
                trigger=trigger,
                bot_config_id=cfg.id,
                platform=platform,
            )
            run_id = run["run_id"]
        try:
            response = (
                await self._sync_qq(cfg, db, run_id=run_id)
                if cfg.platform == BotConfigPlatform.QQ
                else await self._sync_telegram(
                    cfg,
                    db,
                    run_id=run_id,
                )
            )
        except Exception as exc:
            await record_task_run_error(
                "bot_chats_sync",
                run_id,
                exc,
                bot_config_id=cfg.id,
                platform=platform,
            )
            raise

        result = response.model_dump(exclude={"run_id"})
        result.pop("details", None)
        await record_task_run_success(
            "bot_chats_sync",
            run_id,
            **result,
        )
        return response

    async def _sync_telegram(
        self,
        cfg: BotConfig,
        db: AsyncSession,
        *,
        run_id: str,
    ) -> BotConfigSyncChatsResponse:
        result = await refresh_telegram_chats(
            db,
            bot_config=cfg,
            enabled_only=False,
            fetch_permissions=False,
        )
        return BotConfigSyncChatsResponse(
            bot_config_id=cfg.id,
            run_id=run_id,
            total=result["total"],
            updated=result["updated"],
            created=result["created"],
            failed=result["failed"],
            details=result["details"],
        )

    async def _sync_qq(
        self,
        cfg: BotConfig,
        db: AsyncSession,
        *,
        run_id: str,
    ) -> BotConfigSyncChatsResponse:
        if not cfg.napcat_http_url:
            raise ValueError("napcat_http_url is required for qq sync")

        endpoint = cfg.napcat_http_url.rstrip("/") + "/get_group_list"
        headers = {}
        if cfg.napcat_access_token:
            headers["Authorization"] = f"Bearer {cfg.napcat_access_token}"
        try:
            async with self._client_factory(timeout=15.0) as client:
                response = await client.get(endpoint, headers=headers)
                payload = response.json()
        except Exception as exc:
            raise ValueError(f"Failed to fetch napcat group list: {exc}") from exc

        groups = []
        if isinstance(payload, dict) and isinstance(payload.get("data"), list):
            groups = payload["data"]

        details: list[dict[str, Any]] = []
        created = 0
        updated = 0
        failed = 0
        for item in groups:
            try:
                group_id = str(item.get("group_id") or "").strip()
                group_name = item.get("group_name") or f"QQ Group {group_id}"
                if not group_id:
                    continue

                chat = await db.scalar(
                    select(BotChat).where(
                        BotChat.bot_config_id == cfg.id,
                        BotChat.chat_id == group_id,
                    )
                )
                if chat:
                    chat.title = group_name
                    chat.chat_type = BotChatType.QQ_GROUP
                    chat.is_accessible = True
                    chat.last_sync_at = utcnow()
                    chat.sync_error = None
                    updated += 1
                else:
                    db.add(
                        BotChat(
                            bot_config_id=cfg.id,
                            chat_id=group_id,
                            chat_type=BotChatType.QQ_GROUP,
                            title=group_name,
                            is_accessible=True,
                            last_sync_at=utcnow(),
                        )
                    )
                    created += 1
                details.append(
                    {"chat_id": group_id, "title": group_name, "status": "ok"}
                )
                await event_bus.publish(
                    "bot_sync_progress",
                    {
                        "bot_config_id": cfg.id,
                        "chat_id": group_id,
                        "title": group_name,
                        "status": "ok",
                        "updated": updated,
                        "created": created,
                        "failed": failed,
                        "total": len(groups),
                        "timestamp": utcnow().isoformat(),
                    },
                )
            except Exception as exc:
                failed += 1
                details.append({"status": "failed", "error": str(exc)})
                await event_bus.publish(
                    "bot_sync_progress",
                    {
                        "bot_config_id": cfg.id,
                        "status": "failed",
                        "error": str(exc),
                        "updated": updated,
                        "created": created,
                        "failed": failed,
                        "total": len(groups),
                        "timestamp": utcnow().isoformat(),
                    },
                )

        await db.commit()
        await event_bus.publish(
            "bot_sync_completed",
            {
                "bot_config_id": cfg.id,
                "total": len(groups),
                "updated": updated,
                "created": created,
                "failed": failed,
                "timestamp": utcnow().isoformat(),
            },
        )
        return BotConfigSyncChatsResponse(
            bot_config_id=cfg.id,
            run_id=run_id,
            total=len(groups),
            updated=updated,
            created=created,
            failed=failed,
            details=details,
        )


class BotConfigService:
    """Own BotConfig persistence and its observable follow-up work."""

    def __init__(
        self,
        *,
        runtime: TelegramBotRuntimeService,
        chat_sync: BotChatSyncService,
    ) -> None:
        self._runtime = runtime
        self._chat_sync = chat_sync

    @staticmethod
    def _platform_value(platform: BotConfigPlatform | str) -> str:
        return platform.value if isinstance(platform, BotConfigPlatform) else platform

    def validate_payload(
        self,
        payload: BotConfigCreate | BotConfigUpdate,
        platform: BotConfigPlatform | str,
    ) -> None:
        platform_value = self._platform_value(platform)
        if platform_value == BotConfigPlatform.TELEGRAM.value:
            token = getattr(payload, "bot_token", None)
            if token is not None and not token.strip():
                raise BotConfigValidationError("bot_token cannot be empty")
            return

        if platform_value == BotConfigPlatform.QQ.value:
            for field_name in (
                "napcat_http_url",
                "napcat_ws_url",
                "napcat_access_token",
            ):
                value = getattr(payload, field_name, None)
                if value is not None and not value.strip():
                    raise BotConfigValidationError(
                        f"{field_name} cannot be empty"
                    )

    async def to_response(
        self,
        db: AsyncSession,
        cfg: BotConfig,
    ) -> BotConfigResponse:
        chat_count = int(
            await db.scalar(
                select(func.count(BotChat.id)).where(
                    BotChat.bot_config_id == cfg.id
                )
            )
            or 0
        )
        return BotConfigResponse(
            id=cfg.id,
            platform=cfg.platform.value if cfg.platform else "telegram",
            name=cfg.name,
            bot_token_masked=mask_token_partial(cfg.bot_token),
            napcat_http_url=cfg.napcat_http_url,
            napcat_ws_url=cfg.napcat_ws_url,
            napcat_access_token_masked=mask_token_partial(
                cfg.napcat_access_token
            ),
            enabled=bool(cfg.enabled),
            is_primary=bool(cfg.is_primary),
            bot_id=cfg.bot_id,
            bot_username=cfg.bot_username,
            chat_count=chat_count,
            created_at=cfg.created_at,
            updated_at=cfg.updated_at,
        )

    async def list(self, db: AsyncSession) -> list[BotConfigResponse]:
        configs = (
            await db.scalars(
                select(BotConfig).order_by(
                    BotConfig.platform.asc(),
                    BotConfig.id.asc(),
                )
            )
        ).all()
        return [await self.to_response(db, cfg) for cfg in configs]

    async def _mutation_response(
        self,
        db: AsyncSession,
        cfg: BotConfig,
        *,
        reason: str,
        add_task: Callable[..., Any] | None = None,
    ) -> BotConfigMutationResponse:
        follow_up_kind: str | None = None
        follow_up_run_id: str | None = None
        follow_up_status: str | None = None
        follow_up_error: str | None = None

        if cfg.platform == BotConfigPlatform.TELEGRAM:
            result = await self._runtime.sync_process(db, reason=reason)
            follow_up_kind = "bot_runtime_control"
            follow_up_run_id = str(result.get("run_id") or "") or None
            follow_up_status = str(result.get("status") or "") or None
            follow_up_error = str(result.get("error") or "") or None
            logger.info("Telegram bot sync after config mutation: {}", result)
        elif (
            cfg.platform == BotConfigPlatform.QQ
            and cfg.enabled
            and add_task is not None
        ):
            follow_up_kind = "bot_chats_sync"
            follow_up_run_id = await self._chat_sync.schedule_auto_sync(
                cfg.id,
                add_task,
            )
            follow_up_status = "accepted"

        response = await self.to_response(db, cfg)
        return BotConfigMutationResponse(
            **response.model_dump(),
            follow_up_kind=follow_up_kind,
            follow_up_run_id=follow_up_run_id,
            follow_up_status=follow_up_status,
            follow_up_error=follow_up_error,
        )

    async def create(
        self,
        db: AsyncSession,
        payload: BotConfigCreate,
        *,
        add_task: Callable[..., Any],
    ) -> BotConfigMutationResponse:
        self.validate_payload(payload, payload.platform)
        platform = BotConfigPlatform(payload.platform)
        if payload.is_primary:
            await db.execute(
                update(BotConfig)
                .where(BotConfig.platform == platform)
                .values(is_primary=False, updated_at=utcnow())
            )

        cfg = BotConfig(
            platform=platform,
            name=payload.name,
            bot_token=payload.bot_token,
            napcat_http_url=payload.napcat_http_url,
            napcat_ws_url=payload.napcat_ws_url,
            napcat_access_token=payload.napcat_access_token,
            enabled=payload.enabled,
            is_primary=payload.is_primary,
        )
        db.add(cfg)
        await db.commit()
        await db.refresh(cfg)
        logger.info(
            "Bot 配置已创建: id={} name={} platform={}",
            cfg.id,
            cfg.name,
            cfg.platform.value,
        )
        return await self._mutation_response(
            db,
            cfg,
            reason=f"create_config:{cfg.id}",
            add_task=add_task,
        )

    async def update(
        self,
        db: AsyncSession,
        config_id: int,
        payload: BotConfigUpdate,
        *,
        add_task: Callable[..., Any],
    ) -> BotConfigMutationResponse:
        cfg = await db.scalar(select(BotConfig).where(BotConfig.id == config_id))
        if cfg is None:
            raise BotConfigNotFoundError("Bot config not found")
        self.validate_payload(payload, cfg.platform)

        update_data = payload.model_dump(exclude_unset=True)
        if update_data.get("is_primary") is True:
            await db.execute(
                update(BotConfig)
                .where(
                    BotConfig.platform == cfg.platform,
                    BotConfig.id != cfg.id,
                )
                .values(is_primary=False, updated_at=utcnow())
            )
        for key, value in update_data.items():
            setattr(cfg, key, value)
        cfg.updated_at = utcnow()
        await db.commit()
        await db.refresh(cfg)
        logger.info("Bot 配置已更新: id={} name={}", cfg.id, cfg.name)
        return await self._mutation_response(
            db,
            cfg,
            reason=f"update_config:{cfg.id}",
            add_task=add_task,
        )

    async def activate(
        self,
        db: AsyncSession,
        config_id: int,
        *,
        add_task: Callable[..., Any],
    ) -> BotConfigMutationResponse:
        cfg = await db.scalar(select(BotConfig).where(BotConfig.id == config_id))
        if cfg is None:
            raise BotConfigNotFoundError("Bot config not found")
        await db.execute(
            update(BotConfig)
            .where(
                BotConfig.platform == cfg.platform,
                BotConfig.id != cfg.id,
            )
            .values(is_primary=False, updated_at=utcnow())
        )
        cfg.is_primary = True
        cfg.enabled = True
        cfg.updated_at = utcnow()
        await db.commit()
        await db.refresh(cfg)
        logger.info("Bot 配置已激活: id={} name={}", cfg.id, cfg.name)
        return await self._mutation_response(
            db,
            cfg,
            reason=f"activate_config:{cfg.id}",
            add_task=add_task,
        )

    async def delete(
        self,
        db: AsyncSession,
        config_id: int,
    ) -> BotConfigDeleteResponse:
        cfg = await db.scalar(select(BotConfig).where(BotConfig.id == config_id))
        if cfg is None:
            raise BotConfigNotFoundError("Bot config not found")
        platform = cfg.platform
        name = cfg.name
        await db.execute(
            BotChat.__table__.delete().where(BotChat.bot_config_id == cfg.id)
        )
        await db.delete(cfg)
        await db.commit()

        result: dict[str, Any] | None = None
        if platform == BotConfigPlatform.TELEGRAM:
            result = await self._runtime.sync_process(
                db,
                reason=f"delete_config:{config_id}",
            )
            logger.info("Telegram bot sync after delete: {}", result)
        logger.info("Bot 配置已删除: id={} name={}", config_id, name)
        return BotConfigDeleteResponse(
            config_id=config_id,
            follow_up_kind="bot_runtime_control" if result else None,
            follow_up_run_id=(
                str(result.get("run_id") or "") or None if result else None
            ),
            follow_up_status=(
                str(result.get("status") or "") or None if result else None
            ),
            follow_up_error=(
                str(result.get("error") or "") or None if result else None
            ),
        )


def get_bot_runtime_service() -> TelegramBotRuntimeService:
    return TelegramBotRuntimeService()


def get_bot_chat_sync_service() -> BotChatSyncService:
    return BotChatSyncService()
