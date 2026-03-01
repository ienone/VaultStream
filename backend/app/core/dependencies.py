"""
FastAPI Dependencies
"""
from typing import Optional
from fastapi import Header, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.core.config import settings
from app.services.content_service import ContentService
from app.repositories.content_repository import ContentRepository
from app.adapters.storage import get_storage_backend, LocalStorageBackend

def _extract_bearer(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    parts = authorization.split(" ", 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return None

async def require_api_token(
    x_api_token: Optional[str] = Header(default=None, alias="X-API-Token"),
    authorization: Optional[str] = Header(default=None, alias="Authorization"),
):
    expected = settings.api_token.get_secret_value() if settings.api_token else ""
    if not expected:
        return
    provided = x_api_token or _extract_bearer(authorization)
    if not provided or provided != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing API Token")

async def get_content_service(db: AsyncSession = Depends(get_db)) -> ContentService:
    return ContentService(db)

async def get_content_repo(db: AsyncSession = Depends(get_db)) -> ContentRepository:
    return ContentRepository(db)
