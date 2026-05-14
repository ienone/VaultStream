import pytest

from app.core.db_adapter import engine
from app.core.schema_gate import REQUIRED_SCHEMA_VERSION, validate_database_schema


@pytest.mark.asyncio
async def test_database_schema_gate_reports_current_schema():
    async with engine.connect() as conn:
        result = await validate_database_schema(conn)

    assert result["status"] == "ok"
    assert result["schema_version"] >= REQUIRED_SCHEMA_VERSION
    assert result["integrity_check"] == "ok"
    assert result["foreign_key_issues"] == 0
    assert result["fts"]["available"] is True
