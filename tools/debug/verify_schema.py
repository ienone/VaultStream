import sqlite3
import os

db_path = './data/vaultstream.db'
if not os.path.exists(db_path):
    print(f"Error: {db_path} not found")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()
try:
    cursor.execute("PRAGMA table_info(contents)")
    columns = [row[1] for row in cursor.fetchall()]
    print(f"Columns in contents: {columns}")
    
    missing = []
    for col in ['layout_type', 'layout_type_override', 'content_type', 'associated_question', 'top_answers']:
        if col not in columns:
            missing.append(col)
    
    if missing:
        print(f"MISSING COLUMNS: {missing}")
    else:
        print("All expected columns found.")
        
except Exception as e:
    print(f"Error: {e}")
finally:
    conn.close()
