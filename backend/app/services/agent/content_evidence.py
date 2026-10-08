"""Bounded parse-failure evidence shared by Agent reads and capture receipts."""
from app.models import Content, ContentStatus
from app.schemas.agent import ContentParseError

PARSE_ERROR_SCHEMA = {"anyOf": [ContentParseError.model_json_schema(), {"type": "null"}]}


def content_parse_error(content: Content) -> dict | None:
    if content.status != ContentStatus.PARSE_FAILED:
        return None
    return ContentParseError(
        message=(content.last_error[:1999] + "…" if len(content.last_error or "") > 2000
                 else content.last_error),
        type=(content.last_error_type[:199] + "…" if len(content.last_error_type or "") > 200
              else content.last_error_type),
        at=content.last_error_at,
    ).model_dump(mode="json")
