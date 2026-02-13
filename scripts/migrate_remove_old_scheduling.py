"""
数据库迁移脚本：移除旧调度系统字段

用法：
    cd backend
    python ../scripts/migrate_remove_old_scheduling.py

功能：
    从 contents 表中移除以下旧调度系统字段：
    - scheduled_at: 旧的预期分发时间（已被 ContentQueueItem.scheduled_at 替代）
    - is_manual_schedule: 是否手动排期（已无用）

    这些字段属于旧的调度系统（scheduler.py + compact_schedule），
    在迁移到新的队列系统（ContentQueueItem）后不再需要。

何时运行：
    确认新队列系统（ContentQueueItem）稳定运行后执行此脚本。
    执行前请确保已停止后端服务。

注意事项：
    - 脚本会自动备份数据库到 data/vaultstream.db.bak.<timestamp>
    - SQLite >= 3.35.0 支持 ALTER TABLE ... DROP COLUMN，脚本会自动检测版本
    - 低版本 SQLite 会使用重建表的方式移除字段
    - 脚本可安全重复执行（会检查字段是否存在）
"""
import asyncio
import sys
import os
import shutil
import sqlite3
from datetime import datetime

# 添加 backend 目录到 Python 路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'backend'))

import aiosqlite

# 数据库路径（相对于项目根目录）
PROJECT_ROOT = os.path.join(os.path.dirname(__file__), '..')
DB_PATH = os.path.join(PROJECT_ROOT, 'data', 'vaultstream.db')

COLUMNS_TO_REMOVE = ['scheduled_at', 'is_manual_schedule']


def get_sqlite_version() -> tuple[int, ...]:
    """获取 SQLite 版本号"""
    version_str = sqlite3.sqlite_version
    return tuple(int(x) for x in version_str.split('.'))


def supports_drop_column() -> bool:
    """检查 SQLite 是否支持 DROP COLUMN (>= 3.35.0)"""
    version = get_sqlite_version()
    return version >= (3, 35, 0)


def backup_database():
    """备份数据库文件"""
    if not os.path.exists(DB_PATH):
        print(f"❌ 数据库文件不存在: {DB_PATH}")
        sys.exit(1)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_path = f"{DB_PATH}.bak.{timestamp}"
    shutil.copy2(DB_PATH, backup_path)
    print(f"✅ 数据库已备份到: {backup_path}")
    return backup_path


async def get_existing_columns(db: aiosqlite.Connection) -> list[str]:
    """获取 contents 表的所有列名"""
    cursor = await db.execute("PRAGMA table_info(contents)")
    rows = await cursor.fetchall()
    return [row[1] for row in rows]


async def drop_columns_alter(db: aiosqlite.Connection, columns: list[str]):
    """使用 ALTER TABLE DROP COLUMN 移除字段（SQLite >= 3.35.0）"""
    for col in columns:
        print(f"  正在移除字段: {col}")
        await db.execute(f"ALTER TABLE contents DROP COLUMN {col}")
    await db.commit()


async def drop_columns_recreate(db: aiosqlite.Connection, columns_to_remove: list[str]):
    """通过重建表的方式移除字段（兼容旧版 SQLite）"""
    # 1. 获取当前表结构
    cursor = await db.execute("PRAGMA table_info(contents)")
    all_columns_info = await cursor.fetchall()

    # 保留的列（排除要删除的）
    keep_columns = [col for col in all_columns_info if col[1] not in columns_to_remove]
    keep_column_names = [col[1] for col in keep_columns]
    columns_csv = ', '.join(keep_column_names)

    # 2. 获取原始建表语句
    cursor = await db.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='contents'"
    )
    row = await cursor.fetchone()
    if not row:
        print("❌ 无法获取 contents 表的建表语句")
        sys.exit(1)

    original_sql = row[0]

    # 3. 从原始 SQL 中移除要删除的列定义
    # 构建新的建表语句 —— 使用 contents_new 作为临时表名
    new_sql = original_sql.replace('CREATE TABLE contents', 'CREATE TABLE contents_new', 1)
    for col_name in columns_to_remove:
        # 移除列定义行（匹配逗号和换行）
        import re
        # 匹配包含该列名的整行（包括前后的逗号/空白）
        new_sql = re.sub(rf',?\s*{col_name}\s+[^,\)]+', '', new_sql)

    print(f"  创建临时表 contents_new...")
    await db.execute(new_sql)

    # 4. 复制数据
    print(f"  复制数据到新表...")
    await db.execute(f"INSERT INTO contents_new ({columns_csv}) SELECT {columns_csv} FROM contents")

    # 5. 删除旧表
    print(f"  删除旧表...")
    await db.execute("DROP TABLE contents")

    # 6. 重命名新表
    print(f"  重命名 contents_new -> contents...")
    await db.execute("ALTER TABLE contents_new RENAME TO contents")

    # 7. 重建索引（获取原始索引并重建）
    cursor = await db.execute(
        "SELECT sql FROM sqlite_master WHERE type='index' AND tbl_name='contents_new' AND sql IS NOT NULL"
    )
    indexes = await cursor.fetchall()
    for idx_row in indexes:
        idx_sql = idx_row[0].replace('contents_new', 'contents')
        # 跳过引用已删除字段的索引
        skip = False
        for col_name in columns_to_remove:
            if col_name in idx_sql:
                print(f"  跳过旧索引（引用已删除字段）: {idx_sql}")
                skip = True
                break
        if not skip:
            await db.execute(idx_sql)

    await db.commit()


async def main():
    print("=" * 60)
    print("VaultStream 迁移脚本：移除旧调度系统字段")
    print("=" * 60)
    print(f"数据库路径: {os.path.abspath(DB_PATH)}")
    print(f"SQLite 版本: {sqlite3.sqlite_version}")
    print(f"待移除字段: {', '.join(COLUMNS_TO_REMOVE)}")
    print()

    # 1. 备份数据库
    backup_database()

    # 2. 检查哪些字段还存在
    async with aiosqlite.connect(DB_PATH) as db:
        existing_columns = await get_existing_columns(db)
        columns_to_drop = [col for col in COLUMNS_TO_REMOVE if col in existing_columns]

        if not columns_to_drop:
            print("\n✅ 所有目标字段已不存在，无需迁移")
            return

        print(f"\n需要移除的字段: {', '.join(columns_to_drop)}")
        missing = [col for col in COLUMNS_TO_REMOVE if col not in existing_columns]
        if missing:
            print(f"已不存在的字段（跳过）: {', '.join(missing)}")

        # 3. 执行移除
        print()
        if supports_drop_column():
            print("使用 ALTER TABLE DROP COLUMN 方式（SQLite >= 3.35.0）")
            await drop_columns_alter(db, columns_to_drop)
        else:
            print("使用重建表方式（SQLite < 3.35.0 兼容模式）")
            await drop_columns_recreate(db, columns_to_drop)

        # 4. 验证结果
        final_columns = await get_existing_columns(db)
        remaining = [col for col in COLUMNS_TO_REMOVE if col in final_columns]
        if remaining:
            print(f"\n❌ 以下字段仍然存在: {', '.join(remaining)}")
            sys.exit(1)
        else:
            print(f"\n✅ 迁移完成！已成功移除字段: {', '.join(columns_to_drop)}")
            print("💡 请同步移除 SQLAlchemy 模型中对应的字段定义（backend/app/models.py）")


if __name__ == "__main__":
    asyncio.run(main())
