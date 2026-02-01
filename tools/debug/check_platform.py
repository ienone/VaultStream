import sqlite3
import os

db_path = './data/vaultstream.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()
cursor.execute("SELECT DISTINCT platform FROM contents")
print(cursor.fetchall())
conn.close()
