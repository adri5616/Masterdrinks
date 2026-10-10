with open(r'assets/web/app.js', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

idx = text.find("function pintarCajeros()")
if idx != -1:
    print(text[idx:idx+1500])
else:
    print("Not found")
