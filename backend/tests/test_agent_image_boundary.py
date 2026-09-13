from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from PIL import Image
from langchain_core.messages import AIMessage

from app.adapters.storage import LocalStorageBackend
from app.models import Content, Platform
from app.models.media import MediaAsset, MediaType, MediaRole, MediaVariant, MediaVariantKind, MediaVariantStatus
from app.services.agent.tool_registry import AgentToolContext, AgentToolError
from app.services.agent.tools import vision


async def test_image_reading_checks_ownership_and_does_not_persist_binary(db_session, tmp_path, monkeypatch):
    content = Content(url='https://example.com/image', platform=Platform.UNIVERSAL)
    other = Content(url='https://example.com/other-image', platform=Platform.UNIVERSAL)
    db_session.add_all([content, other]); await db_session.flush()
    asset = MediaAsset(content_id=content.id, media_type=MediaType.IMAGE, role=MediaRole.COVER)
    db_session.add(asset); await db_session.flush()
    Image.new('RGB', (20, 20), 'red').save(tmp_path / 'image.png')
    db_session.add(MediaVariant(asset_id=asset.id, variant_kind=MediaVariantKind.ORIGINAL_ARCHIVE,
        status=MediaVariantStatus.READY, storage_key='image.png', mime_type='image/png'))
    await db_session.flush()
    model = AsyncMock(); model.model_name = 'test-vision'
    model.ainvoke.return_value = AIMessage(content='红色图片')
    monkeypatch.setattr(vision.LLMFactory, 'get_vision_llm', AsyncMock(return_value=model))
    monkeypatch.setattr(vision, 'get_storage_backend', lambda: LocalStorageBackend(str(tmp_path)))
    args = {'content_id': other.id, 'media_asset_id': asset.id, 'question': '什么颜色？'}
    with pytest.raises(AgentToolError, match='不存在'):
        await vision.read_image(args, AgentToolContext(db=db_session))
    model.ainvoke.assert_not_called()
    args['content_id'] = content.id
    result = await vision.read_image(args, AgentToolContext(db=db_session))
    assert result['generated'] is True and result['text'] == '红色图片'
    assert 'base64' not in str(result) and str(tmp_path) not in str(result)
    assert model.ainvoke.call_args.args[0][1].content[1]['image_url']['url'].startswith('data:image/jpeg;base64,')
    model.ainvoke.side_effect = RuntimeError('SECRET_PROVIDER_REQUEST_BODY')
    with pytest.raises(AgentToolError) as exc:
        await vision.read_image(args, AgentToolContext(db=db_session))
    assert 'SECRET' not in str(exc.value.to_payload())


def test_image_storage_key_cannot_escape_root(tmp_path):
    storage_root = tmp_path / 'storage'; storage_root.mkdir()
    Image.new('RGB', (10, 10)).save(tmp_path / 'outside.png')
    storage = LocalStorageBackend(str(storage_root))
    with pytest.raises(ValueError, match='invalid image storage key'):
        vision._image_data(storage, '../outside.png')
    (storage_root / 'link.png').symlink_to(tmp_path / 'outside.png')
    with pytest.raises(ValueError, match='invalid image storage key'):
        vision._image_data(storage, 'link.png')
