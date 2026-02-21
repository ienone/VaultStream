-- m21_v2_structure_field_replacement.sql
-- V2 结构字段替换：新增结构化字段。
-- 注意：本 SQL 仅负责 schema 变更；旧字段数据迁移与清理由 backend/scripts/migrate_v2_structure.py 完成。

ALTER TABLE contents ADD COLUMN IF NOT EXISTS context_data JSON;
ALTER TABLE contents ADD COLUMN IF NOT EXISTS rich_payload JSON;
ALTER TABLE contents ADD COLUMN IF NOT EXISTS archive_metadata JSON;
ALTER TABLE contents ADD COLUMN IF NOT EXISTS deleted_at DATETIME;
