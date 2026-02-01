import sqlite3
import os

DB_PATH = "backend/data/vaultstream.db"

def migrate_db():
    if not os.path.exists(DB_PATH):
        print(f"Database not found at {DB_PATH}. Nothing to migrate.")
        return

    print(f"Migrating database: {DB_PATH}")
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 1. 检查 contents 表是否存在 source_type 列
    try:
        cursor.execute("SELECT source_type FROM contents LIMIT 1")
        print("Column 'source_type' already exists.")
    except sqlite3.OperationalError:
        print("Adding 'source_type' column...")
        cursor.execute("ALTER TABLE contents ADD COLUMN source_type VARCHAR(50) DEFAULT 'user_submit'")
        # 创建索引 (SQLite 不支持在 ALTER TABLE 中直接加索引，需要单独加)
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_contents_source_type ON contents (source_type)")

    # 2. 检查 ai_score
    try:
        cursor.execute("SELECT ai_score FROM contents LIMIT 1")
        print("Column 'ai_score' already exists.")
    except sqlite3.OperationalError:
        print("Adding 'ai_score' column...")
        cursor.execute("ALTER TABLE contents ADD COLUMN ai_score FLOAT")

    # 3. 检查 discovered_at
    try:
        cursor.execute("SELECT discovered_at FROM contents LIMIT 1")
        print("Column 'discovered_at' already exists.")
    except sqlite3.OperationalError:
        print("Adding 'discovered_at' column...")
        cursor.execute("ALTER TABLE contents ADD COLUMN discovered_at DATETIME")

    # 4. 检查 discover_topics 表是否存在
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='discover_topics'")
    if not cursor.fetchone():
        print("Creating 'discover_topics' table...")
        cursor.execute("""
            CREATE TABLE discover_topics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name VARCHAR(100) NOT NULL,
                keywords JSON,
                platforms JSON,
                enabled BOOLEAN DEFAULT 1,
                priority INTEGER DEFAULT 5,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_discover_topics_enabled ON discover_topics (enabled)")

    # 5. 检查 discover_sources 表是否存在
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='discover_sources'")
    if not cursor.fetchone():
        print("Creating 'discover_sources' table...")
        cursor.execute("""
            CREATE TABLE discover_sources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type VARCHAR(50) NOT NULL,
                name VARCHAR(100) NOT NULL,
                config JSON,
                schedule VARCHAR(100),
                enabled BOOLEAN DEFAULT 1,
                last_run_at DATETIME,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        """)
        cursor.execute("CREATE INDEX IF NOT EXISTS ix_discover_sources_enabled ON discover_sources (enabled)")

    conn.commit()
    conn.close()
    print("Migration completed successfully.")

if __name__ == "__main__":
    migrate_db()
