import asyncio
import sqlite3
import os
from pathlib import Path
from app.config import settings

async def apply_m3_migration():
    db_path = settings.sqlite_db_path
    sql_path = Path("migrations/m3_indexes_and_fts.sql")
    
    if not os.path.exists(db_path):
        print(f"数据库文件 {db_path} 不存在，跳过。")
        return
        
    print(f"正在应用 M3 迁移到 {db_path}...")
    
    # SQLite 直接连接运行 SQL 脚本
    conn = sqlite3.connect(db_path)
    try:
        with open(sql_path, 'r', encoding='utf-8') as f:
            sql_script = f.read()
        
        # 允许多条语句执行
        conn.executescript(sql_script)
        conn.commit()
        print("M3 迁移应用成功（索引与 FTS5 已就绪）。")
    except sqlite3.Error as e:
        print(f"执行 SQL 出错: {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    asyncio.run(apply_m3_migration())
