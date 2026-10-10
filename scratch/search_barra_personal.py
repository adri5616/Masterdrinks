with open(r'assets/web/app.js', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

import re
matches = [m.start() for m in re.finditer(r'barra', text, re.IGNORECASE)]
print(f"Total 'barra' in app.js: {len(matches)}")

# Search for places where barra is loaded or displayed in config or personal
for kw in ['id_barra', 'nombre_barra', 'select-barra', 'barra-cajero', 'barra_nombre']:
    m2 = [m.start() for m in re.finditer(kw, text, re.IGNORECASE)]
    print(f"Matches for {kw}: {len(m2)}")
    for idx in m2[:3]:
        print(f"--- {kw} ---")
        print(text[max(0, idx-100):min(len(text), idx+200)])
