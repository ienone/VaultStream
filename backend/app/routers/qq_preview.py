"""Authenticated Koishi entry point for anonymous group link previews."""

from fastapi import APIRouter, Depends

from app.core.dependencies import require_api_token
from app.schemas.qq_preview import QQPreviewRequest, QQPreviewResponse
from app.services.qq_preview import preview_group_links


router = APIRouter()


@router.post("/bot/qq/{config_id}/preview", response_model=QQPreviewResponse)
async def preview_links(
    config_id: int,
    request: QQPreviewRequest,
    _: None = Depends(require_api_token),
) -> QQPreviewResponse:
    return await preview_group_links(config_id, request)
