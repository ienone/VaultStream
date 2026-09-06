"""Knowledge-event API: explicit grouping, classification and evidence links."""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.api_errors import build_error_payload
from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.models import KnowledgeEventStatus
from app.schemas.knowledge_event import (
    KnowledgeEventCreate,
    KnowledgeEventDetailResponse,
    KnowledgeEventListResponse,
    KnowledgeEventMemberCreate,
    KnowledgeEventMemberRemoveResponse,
    KnowledgeEventMemberUpdate,
    KnowledgeEventUpdate,
)
from app.services.knowledge_event_service import KnowledgeEventError, KnowledgeEventService

router = APIRouter()


def _raise_event_error(error: KnowledgeEventError) -> None:
    raise HTTPException(
        status_code=error.status_code,
        detail=build_error_payload(message=error.message, code=error.code),
    ) from error


@router.get("/knowledge-events", response_model=KnowledgeEventListResponse)
async def list_knowledge_events(
    page: int = Query(1, ge=1),
    size: int = Query(20, ge=1, le=100),
    status: KnowledgeEventStatus | None = Query(None),
    content_id: int | None = Query(None, gt=0),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    return await KnowledgeEventService(db).list_events(
        page=page,
        size=size,
        status=status,
        content_id=content_id,
    )


@router.post(
    "/knowledge-events",
    response_model=KnowledgeEventDetailResponse,
    status_code=201,
)
async def create_knowledge_event(
    request: KnowledgeEventCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        return await KnowledgeEventService(db).create_event(request)
    except KnowledgeEventError as error:
        _raise_event_error(error)


@router.get(
    "/knowledge-events/{event_id}",
    response_model=KnowledgeEventDetailResponse,
)
async def get_knowledge_event(
    event_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        return await KnowledgeEventService(db).get_event(event_id)
    except KnowledgeEventError as error:
        _raise_event_error(error)


@router.patch(
    "/knowledge-events/{event_id}",
    response_model=KnowledgeEventDetailResponse,
)
async def update_knowledge_event(
    event_id: int,
    request: KnowledgeEventUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        return await KnowledgeEventService(db).update_event(event_id, request)
    except KnowledgeEventError as error:
        _raise_event_error(error)


@router.post(
    "/knowledge-events/{event_id}/members",
    response_model=KnowledgeEventDetailResponse,
)
async def add_knowledge_event_member(
    event_id: int,
    request: KnowledgeEventMemberCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        return await KnowledgeEventService(db).add_member(event_id, request)
    except KnowledgeEventError as error:
        _raise_event_error(error)


@router.patch(
    "/knowledge-events/{event_id}/members/{content_id}",
    response_model=KnowledgeEventDetailResponse,
)
async def update_knowledge_event_member(
    event_id: int,
    content_id: int,
    request: KnowledgeEventMemberUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        return await KnowledgeEventService(db).update_member(
            event_id,
            content_id,
            request,
        )
    except KnowledgeEventError as error:
        _raise_event_error(error)


@router.delete(
    "/knowledge-events/{event_id}/members/{content_id}",
    response_model=KnowledgeEventMemberRemoveResponse,
)
async def remove_knowledge_event_member(
    event_id: int,
    content_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        return await KnowledgeEventService(db).remove_member(event_id, content_id)
    except KnowledgeEventError as error:
        _raise_event_error(error)
