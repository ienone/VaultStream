from uuid import uuid4

import pytest

from app.models import Content, Platform
from app.utils.text_search import fetch_fts_content_ids


@pytest.mark.asyncio
async def test_content_fts_indexes_insert_update_and_delete(db_session):
    unique_token = f"vaultstreamfts{uuid4().hex}"
    updated_token = f"vaultstreamfts{uuid4().hex}"

    content = Content(
        platform=Platform.ZHIHU,
        url=f"https://example.com/{unique_token}",
        canonical_url=f"https://example.com/{unique_token}",
        title=f"Initial {unique_token}",
        body="FTS body",
        summary="FTS summary",
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)

    inserted_ids = await fetch_fts_content_ids(session=db_session, query=unique_token)
    assert content.id in inserted_ids

    content.title = f"Updated {updated_token}"
    await db_session.commit()

    stale_ids = await fetch_fts_content_ids(session=db_session, query=unique_token)
    current_ids = await fetch_fts_content_ids(session=db_session, query=updated_token)
    assert content.id not in stale_ids
    assert content.id in current_ids

    await db_session.delete(content)
    await db_session.commit()

    deleted_ids = await fetch_fts_content_ids(session=db_session, query=updated_token)
    assert content.id not in deleted_ids
