with open(r'assets/web/app.js', 'r', encoding='utf-8', errors='ignore') as f:
    text = f.read()

import re
matches = [m.start() for m in re.finditer(r'/api/admin/cajeros', text)]
for idx in matches:
    print('--- MATCH ---')
    print(text[max(0, idx-300):min(len(text), idx+500)])
