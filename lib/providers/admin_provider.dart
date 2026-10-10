import 'package:flutter/material.dart';
import '../data/models/models.dart';
import '../services/api_service.dart';
import '../services/pdf_report_service.dart';

class AdminProvider extends ChangeNotifier {
  EventConfigModel? _config;
  List<Map<String, dynamic>> _cajeros = [];
  List<Map<String, dynamic>> _meseros = [];
  List<Map<String, dynamic>> _comandas = [];
  Map<String, dynamic> _reporte = {};
  List<Map<String, dynamic>> _auditoria = [];
  bool _isLoading = false;
  String? _error;

  EventConfigModel? get config => _config;
  List<Map<String, dynamic>> get cajeros => _cajeros;
  List<Map<String, dynamic>> get meseros => _meseros;
  List<Map<String, dynamic>> get comandas => _comandas;
  Map<String, dynamic> get reporte => _reporte;
  List<Map<String, dynamic>> get auditoria => _auditoria;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadConfig() async {
    try {
      _config = await ApiService.instance.getConfiguracion();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> updateConfig(EventConfigModel newConfig) async {
    _isLoading = true;
    notifyListeners();
    final ok = await ApiService.instance.updateConfiguracion(newConfig);
    if (ok) {
      _config = newConfig;
    }
    _isLoading = false;
    notifyListeners();
    return ok;
  }

  Future<void> loadPersonal() async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.instance.getPersonal();
      _cajeros = List<Map<String, dynamic>>.from(data['cajeros'] ?? []);
      _meseros = List<Map<String, dynamic>>.from(data['meseros'] ?? []);
    } catch (e) {
      _error = 'Error cargando personal: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> crearCajero(String nombre, String usuario, String password) async {
    final ok = await ApiService.instance.crearCajero(nombre, usuario, password);
    if (ok) await loadPersonal();
    return ok;
  }

  Future<bool> eliminarCajero(int idCajero) async {
    final ok = await ApiService.instance.eliminarCajero(idCajero);
    if (ok) await loadPersonal();
    return ok;
  }

  Future<bool> crearMesero(String nombre, String usuario, String pin, int idCajero) async {
    final ok = await ApiService.instance.crearMesero(nombre, usuario, pin, idCajero);
    if (ok) await loadPersonal();
    return ok;
  }

  Future<bool> eliminarMesero(int idMesero) async {
    final ok = await ApiService.instance.eliminarMesero(idMesero);
    if (ok) await loadPersonal();
    return ok;
  }

  Future<void> loadComandas() async {
    _isLoading = true;
    notifyListeners();
    try {
      _comandas = await ApiService.instance.getComandas();
    } catch (e) {
      _error = 'Error cargando comandas: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> anularComanda(int idComanda, int idAdmin, String motivo) async {
    final ok = await ApiService.instance.anularComanda(idComanda, idAdmin, motivo);
    if (ok) await loadComandas();
    return ok;
  }

  Future<void> loadReporte() async {
    _isLoading = true;
    notifyListeners();
    try {
      _reporte = await ApiService.instance.getReporte();
    } catch (e) {
      _error = 'Error cargando reporte: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> exportarPdfCierre() async {
    if (_config == null) await loadConfig();
    if (_reporte.isEmpty) await loadReporte();

    await PdfReportService.instance.generarReporteCierre(
      config: _config!,
      datosReporte: _reporte,
    );
  }

  Future<void> loadAuditoria() async {
    _isLoading = true;
    notifyListeners();
    try {
      _auditoria = await ApiService.instance.getAuditoria();
    } catch (e) {
      _error = 'Error cargando auditoría: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> registrarAjusteStock(int idProd, String tipo, int cantidad, String motivo, int idAdmin) async {
    final ok = await ApiService.instance.registrarMovimientoStock(idProd, tipo, cantidad, motivo, idAdmin);
    return ok;
  }

  Future<bool> crearProducto(Map<String, dynamic> data) async {
    final ok = await ApiService.instance.crearProducto(data);
    return ok;
  }

  Future<bool> eliminarProducto(int idProducto) async {
    final ok = await ApiService.instance.eliminarProducto(idProducto);
    return ok;
  }
}
