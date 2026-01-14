-- M5: Add cover_color field to contents table
ALTER TABLE contents ADD COLUMN IF NOT EXISTS cover_color VARCHAR(20);
