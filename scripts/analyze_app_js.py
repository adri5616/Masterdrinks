import re

with open(r'assets/web/app.js', 'r', encoding='utf-8') as f:
    app_js = f.read()

# Let's find sections for inventario or stock
print("--- SEARCHING INVENTARIO / STOCK IN app.js ---")
lines = app_js.splitlines()
for idx, line in enumerate(lines):
    if any(k in line.lower() for k in ['tab-stock', 'tab-inventario', 'cargarstock', 'cargarinventario', 'cargarmovimientos', 'cargarrostros']):
        print(f"L{idx+1}: {line.strip()[:100]}")

print("\n--- ALL FETCH URLS IN app.js ---")
fetch_urls = set(re.findall(r'fetch\([\'"`]([^\'"`$]+)', app_js))
for u in sorted(fetch_urls):
    print(u)
