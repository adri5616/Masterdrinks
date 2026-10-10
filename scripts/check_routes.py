import re

with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8') as f:
    text = f.read()

pattern = r'app\.(get|post|put|delete)\s*\(\s*[\'"]([^\'"]+)[\'"]'
matches = re.findall(pattern, text)
print(f"Total routes in server.js: {len(matches)}")
for m, r in matches:
    print(f"{m.upper():6} {r}")
