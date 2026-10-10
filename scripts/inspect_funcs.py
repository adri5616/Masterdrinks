with open(r'assets/web/app.js', 'r', encoding='utf-8') as f:
    text = f.read()

def show_block(pattern_str, length=50):
    lines = text.splitlines()
    for i, l in enumerate(lines):
        if pattern_str in l:
            print(f"=== Found '{pattern_str}' at line {i+1} ===")
            for j in range(max(0, i-2), min(len(lines), i+length)):
                # sanitize any emojis for windows console
                safe_l = lines[j].encode('ascii', errors='replace').decode('ascii')
                print(f"{j+1}: {safe_l}")
            break

show_block('function cargarTraspasos')
show_block('function loadInventoryData')
show_block('async function cargarRostrosAdmin')
