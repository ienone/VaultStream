-- m21_v2_structure_field_replacement.sql
-- V2 结构字段替换：新增结构化字段，并清理旧字段数据。

ALTER TABLE contents ADD COLUMN context_data JSON;
ALTER TABLE contents ADD COLUMN rich_payload JSON;
ALTER TABLE contents ADD COLUMN archive_metadata JSON;
ALTER TABLE contents ADD COLUMN deleted_at DATETIME;

-- 迁移后统一清空旧字段，避免新旧字段混用造成语义歧义。
UPDATE contents SET raw_metadata = NULL WHERE raw_metadata IS NOT NULL;
UPDATE contents SET associated_question = NULL WHERE associated_question IS NOT NULL;
UPDATE contents SET top_answers = NULL WHERE top_answers IS NOT NULL;
