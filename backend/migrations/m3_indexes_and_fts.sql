-- M3: SQLite Index Optimization & FTS5 Full Text Search

-- 1. 复合索引 (加速过滤与排序)
CREATE INDEX IF NOT EXISTS ix_contents_platform_created_at ON contents (platform, created_at);
CREATE INDEX IF NOT EXISTS ix_contents_status_created_at ON contents (status, created_at);
CREATE INDEX IF NOT EXISTS ix_contents_is_nsfw_created_at ON contents (is_nsfw, created_at);

-- 2. FTS5 全文搜索表
-- 我们将 title, description, author_name 放入搜索索引
CREATE VIRTUAL TABLE IF NOT EXISTS contents_fts USING fts5(
    content_id UNINDEXED,
    title,
    description,
    author_name,
    content='contents',
    content_rowid='id'
);

-- 3. 触发器：自动同步 FTS 索引

-- 插入触发器
CREATE TRIGGER IF NOT EXISTS contents_ai AFTER INSERT ON contents BEGIN
  INSERT INTO contents_fts(rowid, content_id, title, description, author_name)
  VALUES (new.id, new.id, new.title, new.description, new.author_name);
END;

-- 删除触发器
CREATE TRIGGER IF NOT EXISTS contents_ad AFTER DELETE ON contents BEGIN
  INSERT INTO contents_fts(contents_fts, rowid, content_id, title, description, author_name)
  VALUES('delete', old.id, old.id, old.title, old.description, old.author_name);
END;

-- 更新触发器
CREATE TRIGGER IF NOT EXISTS contents_au AFTER UPDATE ON contents BEGIN
  INSERT INTO contents_fts(contents_fts, rowid, content_id, title, description, author_name)
  VALUES('delete', old.id, old.id, old.title, old.description, old.author_name);
  INSERT INTO contents_fts(rowid, content_id, title, description, author_name)
  VALUES (new.id, new.id, new.title, new.description, new.author_name);
END;

-- 4. 初始化现有的数据到 FTS
INSERT OR IGNORE INTO contents_fts(rowid, content_id, title, description, author_name)
SELECT id, id, title, description, author_name FROM contents;
