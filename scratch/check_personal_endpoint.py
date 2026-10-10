with open(r'lib/server/embedded_server.dart', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

idx = text.find("router.get('/api/admin/personal'")
if idx != -1:
    print(text[idx:idx+800])
else:
    print("Not found")
