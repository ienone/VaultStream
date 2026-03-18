-- Drop redundant index on primary key column `system_settings.key`.
-- Primary key already creates sqlite_autoindex_system_settings_1.
DROP INDEX IF EXISTS ix_system_settings_key;
