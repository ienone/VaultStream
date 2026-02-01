import sqlite3
import os

db_path = './data/vaultstream.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
cursor.execute("SELECT id, url, content_type, layout_type FROM contents WHERE platform = 'BILIBILI'")
rows = cursor.fetchall()
for row in rows:
    print(row)
conn.close()
