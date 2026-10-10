with open(r'assets/web/index.html', 'r', encoding='utf-8') as f:
    html = f.read()

import re
tabs = set(re.findall(r'data-tab="([^"]+)"', html))
print('Tabs in index.html:', tabs)

for i, line in enumerate(html.splitlines()):
    if any(k in line.lower() for k in ['inventario', 'stock']):
        safe_l = line.encode('ascii', errors='replace').decode('ascii')
        print(f"L{i+1}: {safe_l.strip()[:100]}")
