import re

with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8') as f:
    text = f.read()

missing_list = [
    '/api/admin/productos/:id/movimientos',
    '/api/admin/productos/:id/estado',
    '/api/admin/productos/:id/acompanamiento',
    '/api/admin/productos/:id/foto',
    '/api/admin/categorias/:id/estado',
    '/api/admin/cajeros/:id/estado',
    '/api/admin/meseros/:id/estado',
    '/api/admin/encargados',
    '/api/promocion/:id/foto',
    '/api/admin/promociones/:id/foto',
]

for r in missing_list:
    pos = text.find(r)
    print(f"\n================ ROUTE: {r} (pos={pos}) ================")
    if pos != -1:
        # print up to next app.
        next_app = text.find('app.', pos + len(r))
        if next_app == -1: next_app = pos + 1000
        safe_str = text[pos-10:next_app].encode('ascii', errors='replace').decode('ascii')
        print(safe_str[:1200])
