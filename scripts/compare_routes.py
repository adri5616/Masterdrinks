import re

with open(r'lib/server/embedded_server.dart', 'r', encoding='utf-8') as f:
    text_server = f.read()

with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8') as f:
    text_js = f.read()

pattern = r'app\.(get|post|put|delete)\s*\(\s*[\'"]([^\'"]+)[\'"]'
matches = re.findall(pattern, text_js)

print("ROUTES COMPARISON:")
for m, r in matches:
    # check if r (ignoring :id params) is in embedded_server.dart
    base_route = re.sub(r':\w+', '', r)
    if base_route not in text_server:
        print(f"MISSING: {m.upper():6} {r}")

print("\n--- APP.JS CALLS RELATED TO INVENTARIO / STOCK ---")
with open(r'assets/www/app.js', 'r', encoding='utf-8') as f:
    app_js = f.read()

stock_calls = set(re.findall(r'fetch\([\'"`]([^\'"`]+)[\'"`]', app_js))
for call in sorted(stock_calls):
    if any(k in call.lower() for k in ['stock', 'inventario', 'traspaso', 'catalogo', 'rostro', 'producto']):
        print("fetch ->", call)
