-- 迁移脚本：将 tags 列从 JSON 改为 JSONB
-- 这样可以使用 PostgreSQL 的 JSONB 操作符（如 @>, ? 等）进行高效查询

-- 修改 contents 表的 JSON 列类型
ALTER TABLE contents 
ALTER COLUMN tags TYPE JSONB USING tags::jsonb;

ALTER TABLE contents 
ALTER COLUMN extra_stats TYPE JSONB USING extra_stats::jsonb;

ALTER TABLE contents 
ALTER COLUMN raw_metadata TYPE JSONB USING raw_metadata::jsonb;

ALTER TABLE contents 
ALTER COLUMN media_urls TYPE JSONB USING media_urls::jsonb;

ALTER TABLE contents 
ALTER COLUMN last_error_detail TYPE JSONB USING last_error_detail::jsonb;

-- 修改 content_sources 表的 JSON 列类型
ALTER TABLE content_sources
ALTER COLUMN tags_snapshot TYPE JSONB USING tags_snapshot::jsonb;

ALTER TABLE content_sources
ALTER COLUMN client_context TYPE JSONB USING client_context::jsonb;

-- 为 tags 列创建 GIN 索引以加速 contains 查询
CREATE INDEX IF NOT EXISTS idx_contents_tags ON contents USING GIN (tags);

-- 验证修改
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'contents' 
  AND column_name IN ('tags', 'extra_stats', 'raw_metadata', 'media_urls', 'last_error_detail')
UNION ALL
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'content_sources'
  AND column_name IN ('tags_snapshot', 'client_context')
ORDER BY column_name;
