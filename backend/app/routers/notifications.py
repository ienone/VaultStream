from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.api_errors import build_error_payload
from app.core.dependencies import require_api_token
from app.schemas.notifications import (
    NotificationActionRequest,
    NotificationDigestResponse,
    NotificationInboxResponse,
    NotificationMessageResponse,
    NotificationReadAllResponse,
    NotificationState,
)
from app.services.notification_inbox import (
    apply_notification_action,
    list_notifications,
    mark_all_notifications_read,
)
from app.services.notification_digest import create_activity_digest

router = APIRouter()


@router.get("/notifications", response_model=NotificationInboxResponse)
async def get_notifications(
    category: str | None = Query(None, max_length=32),
    state: NotificationState = Query("active"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    _: None = Depends(require_api_token),
):
    return await list_notifications(
        category=category,
        state=state,
        limit=limit,
        offset=offset,
    )


@router.post(
    "/notifications/{notification_id}/actions",
    response_model=NotificationMessageResponse,
)
async def update_notification(
    notification_id: int,
    request: NotificationActionRequest,
    _: None = Depends(require_api_token),
):
    try:
        item = await apply_notification_action(
            notification_id,
            action=request.action,
            snoozed_until=request.snoozed_until,
        )
    except ValueError as error:
        raise HTTPException(
            status_code=400,
            detail=build_error_payload(
                message=str(error),
                code="invalid_notification_action",
            ),
        ) from error
    if item is None:
        raise HTTPException(
            status_code=404,
            detail=build_error_payload(
                message="Notification not found",
                code="notification_not_found",
            ),
        )
    return item


@router.post("/notifications/read-all", response_model=NotificationReadAllResponse)
async def read_all_notifications(_: None = Depends(require_api_token)):
    return {"changed": await mark_all_notifications_read()}


@router.post("/notifications/digest", response_model=NotificationDigestResponse)
async def generate_notification_digest(_: None = Depends(require_api_token)):
    """Explicitly check persisted activity and create a digest when facts changed."""
    return await create_activity_digest()
