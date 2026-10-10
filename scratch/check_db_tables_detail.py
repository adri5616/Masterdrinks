import sqlite3

conn = sqlite3.connect('assets/db/pos_evento.db')
c = conn.cursor()
tables = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
print("Tables:", tables)

if 'instancia' in tables:
    print("instancia:", c.execute("SELECT * FROM instancia").fetchall())
else:
    print("Table 'instancia' DOES NOT EXIST!")

if 'configuracion' in tables:
    print("configuracion:", c.execute("SELECT * FROM configuracion").fetchall())

print("evento:", c.execute("SELECT * FROM evento").fetchall())
print("barra:", c.execute("SELECT * FROM barra").fetchall())
