import 'package:flutter/material.dart';
import '../data/models/models.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  WaiterModel? _currentWaiter;
  bool _isWaiterLocked = true;
  String? _errorMessage;
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  WaiterModel? get currentWaiter => _currentWaiter;
  bool get isWaiterLocked => _isWaiterLocked;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;

  bool get isAuthenticated => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isCajero => _currentUser?.isCajero ?? false;

  Future<bool> login(String usuario, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.login(usuario, password);
      if (res['success'] == true) {
        final u = (res['user'] ?? res['usuario']) as Map<String, dynamic>;
        _currentUser = UserModel.fromMap(u, res['rol'] ?? 'CAJERO');
        _isWaiterLocked = true;
        _currentWaiter = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = res['message'] ?? 'Credenciales inválidas';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'No se pudo conectar al servidor: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginAdminPin(String pin) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.loginAdminPin(pin);
      if (res['success'] == true) {
        final u = (res['user'] ?? res['usuario']) as Map<String, dynamic>;
        _currentUser = UserModel.fromMap(u, res['rol'] ?? 'ADMINISTRADOR');
        _isWaiterLocked = true;
        _currentWaiter = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = res['message'] ?? 'PIN de administrador incorrecto';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error al validar PIN: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginAdminFacial(List<dynamic> descriptor) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.loginAdminFacial(descriptor);
      if (res['success'] == true) {
        final u = (res['user'] ?? res['usuario']) as Map<String, dynamic>;
        _currentUser = UserModel.fromMap(u, res['rol'] ?? 'ADMINISTRADOR');
        _isWaiterLocked = true;
        _currentWaiter = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = res['message'] ?? 'Rostro no reconocido';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error en autenticación facial: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockWaiter(String pin) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.loginMesero(pin);
      if (res['success'] == true) {
        final m = res['mesero'] as Map<String, dynamic>;
        _currentWaiter = WaiterModel.fromMap(m);
        _isWaiterLocked = false;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = res['message'] ?? 'PIN de mesero incorrecto';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error al validar PIN: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void lockWaiter() {
    _isWaiterLocked = true;
    _currentWaiter = null;
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    _currentWaiter = null;
    _isWaiterLocked = true;
    _errorMessage = null;
    notifyListeners();
  }
}
