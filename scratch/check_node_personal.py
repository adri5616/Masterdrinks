with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

idx = text.find("app.get('/api/admin/personal'")
if idx != -1:
    print(text[idx:idx+1200])
else:
    print("Not found")
