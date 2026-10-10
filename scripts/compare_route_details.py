with open(r'lib/server/embedded_server.dart', 'r', encoding='utf-8') as f:
    text_server = f.read()

with open(r'C:\Users\adri5\OneDrive\Desktop\MasterDrinks2\server.js', 'r', encoding='utf-8') as f:
    text_js = f.read()

def extract_js_route(route_path):
    print(f"\n================ JS ROUTE: {route_path} ================")
    pos = text_js.find(route_path)
    if pos != -1:
        print(text_js[pos-10:pos+800])
    else:
        print("Not found in server.js")

def extract_dart_route(route_path):
    print(f"\n================ DART ROUTE: {route_path} ================")
    pos = text_server.find(route_path)
    if pos != -1:
        print(text_server[pos-10:pos+800])
    else:
        print("Not found in embedded_server.dart")

extract_js_route("'/api/productos'")
extract_dart_route("'/api/productos'")

extract_js_route("'/api/traspasos'")
extract_dart_route("'/api/traspasos'")

extract_js_route("'/api/admin/rostros'")
extract_dart_route("'/api/admin/rostros'")
