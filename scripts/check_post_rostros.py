with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8') as f:
    text = f.read()

pos = text.find("app.post('/api/admin/rostros'")
if pos != -1:
    print(text[pos:pos+900].encode('ascii', errors='replace').decode('ascii'))
