import 'dart:convert';
import 'package:http/http.dart' as http;
import '../data/models/models.dart';

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  String baseUrl = 'http://127.0.0.1:3000';

  void setBaseUrl(String url) {
    if (url.endsWith('/')) {
      baseUrl = url.substring(0, url.length - 1);
    } else {
      baseUrl = url;
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }
  }

  Future<Map<String, dynamic>> login(String usuario, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'usuario': usuario, 'password': password}),
    );
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> loginMesero(String pin) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login/mesero'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'pin': pin}),
    );
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> loginAdminPin(String pin) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login/admin-pin'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'password': pin, 'pin': pin}),
    );
    return jsonDecode(res.body);
  }

  Future<Map<String, dynamic>> loginAdminFacial(List<dynamic> liveDescriptor) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/login/admin-facial'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'liveDescriptor': liveDescriptor}),
    );
    return jsonDecode(res.body);
  }

  Future<EventConfigModel> getConfiguracion() async {
    final res = await http.get(Uri.parse('$baseUrl/api/configuracion'));
    if (res.statusCode == 200) {
      return EventConfigModel.fromMap(jsonDecode(res.body));
    }
    return EventConfigModel(
      evento: 'MasterDrinks Evento',
      fecha: '',
      lugar: '',
      barra: 'Barra 1',
      responsable: '',
    );
  }

  Future<bool> updateConfiguracion(EventConfigModel config) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/admin/configuracion-evento'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'evento': config.evento,
        'fecha': config.fecha,
        'lugar': config.lugar,
        'barra': config.barra,
        'responsable': config.responsable,
      }),
    );
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>> getProductosYCategorias() async {
    final res = await http.get(Uri.parse('$baseUrl/api/productos'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Error al cargar productos');
  }

  Future<List<Map<String, dynamic>>> getStock() async {
    final res = await http.get(Uri.parse('$baseUrl/api/stock'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }

  Future<Map<String, dynamic>> crearComanda({
    required int idCajero,
    required int? idMesero,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> pagos,
    required double total,
    required String claveIdempotencia,
    String? observaciones,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/comanda'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'id_cajero': idCajero,
        'id_mesero': idMesero,
        'items': items,
        'pagos': pagos,
        'total': total,
        'clave_idempotencia': claveIdempotencia,
        'observaciones': observaciones,
      }),
    );
    return jsonDecode(res.body);
  }

  Future<List<Map<String, dynamic>>> getComandas() async {
    final res = await http.get(Uri.parse('$baseUrl/api/admin/comandas'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }

  Future<bool> anularComanda(int idComanda, int idAdmin, String motivo) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/comandas/anular'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'id_comanda': idComanda,
        'id_admin': idAdmin,
        'motivo': motivo,
      }),
    );
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>> getPersonal() async {
    final res = await http.get(Uri.parse('$baseUrl/api/admin/personal'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {'cajeros': [], 'meseros': []};
  }

  Future<bool> crearCajero(String nombre, String usuario, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/cajeros'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'nombre': nombre, 'usuario': usuario, 'password': password}),
    );
    return res.statusCode == 200;
  }

  Future<bool> eliminarCajero(int idCajero) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/admin/cajeros/$idCajero'));
    return res.statusCode == 200;
  }

  Future<bool> crearMesero(String nombre, String usuario, String pin, int idCajero) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/meseros'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'nombre': nombre,
        'usuario': usuario,
        'password': pin,
        'id_cajero': idCajero,
      }),
    );
    return res.statusCode == 200;
  }

  Future<bool> eliminarMesero(int idMesero) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/admin/meseros/$idMesero'));
    return res.statusCode == 200;
  }

  Future<bool> crearProducto(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/productos'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(data),
    );
    return res.statusCode == 200;
  }

  Future<bool> actualizarProducto(int id, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('$baseUrl/api/admin/productos/$id'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(data),
    );
    return res.statusCode == 200;
  }

  Future<bool> eliminarProducto(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/admin/productos/$id'));
    return res.statusCode == 200;
  }

  Future<bool> registrarMovimientoStock(int idProd, String tipo, int cantidad, String motivo, int idAdmin) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/admin/stock/movimiento'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'id_producto': idProd,
        'tipo_movimiento': tipo,
        'cantidad': cantidad,
        'motivo': motivo,
        'id_admin': idAdmin,
      }),
    );
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>> getReporte() async {
    final res = await http.get(Uri.parse('$baseUrl/api/admin/reporte'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> getAuditoria() async {
    final res = await http.get(Uri.parse('$baseUrl/api/admin/auditoria'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }
}
