with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8') as f:
    text = f.read()

pos = text.find('/api/admin/stock/movimiento')
if pos != -1:
    print(text[pos-10:pos+1500].encode('ascii', errors='replace').decode('ascii'))
