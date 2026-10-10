with open(r'lib/server/embedded_server.dart', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

for ep in ['/api/instancia', '/api/configuracion', '/api/admin/configuracion']:
    idx = text.find(f"'{ep}'")
    if idx != -1:
        print(f"=== {ep} ===")
        print(text[idx:idx+600])
