with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

for ep in ["app.get('/api/configuracion'", "app.get('/api/instancia'", "function leerConfiguracion", "const INSTANCIA"]:
    idx = text.find(ep)
    if idx != -1:
        print(f"=== {ep} ===")
        print(text[idx:idx+800])
