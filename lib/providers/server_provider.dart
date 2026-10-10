import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../server/embedded_server.dart';
import '../services/api_service.dart';

class ServerProvider extends ChangeNotifier {
  bool _isInitialized = false;
  String? _tabletRole; // 'SERVER' o 'CLIENT'
  bool _isServerRunning = false;
  String _serverIp = '127.0.0.1';
  int _serverPort = 3000;
  int _requestCount = 0;
  int _clientsCount = 0;
  bool _wakeLockEnabled = true;
  Timer? _maintenanceTimer;

  // Modo Cliente
  String _clientServerIp = '192.168.43.1';
  int _clientServerPort = 3000;

  bool get isInitialized => _isInitialized;
  String? get tabletRole => _tabletRole;
  bool get isConfigured => _tabletRole != null;
  bool get isServerRole => _tabletRole == 'SERVER';
  bool get isClientRole => _tabletRole == 'CLIENT';
  bool get isClientMode => isClientRole;

  bool get isServerRunning => _isServerRunning;
  String get serverIp => _serverIp;
  int get serverPort => _serverPort;
  int get requestCount => _requestCount;
  int get clientsCount => _clientsCount;
  bool get wakeLockEnabled => _wakeLockEnabled;

  String get clientServerIp => _clientServerIp;
  int get clientServerPort => _clientServerPort;

  String get effectiveWebUrl {
    if (isClientRole) {
      final ip = _clientServerIp.trim().replaceAll('http://', '').replaceAll('/', '');
      return 'http://$ip:$_clientServerPort/';
    }
    return 'http://127.0.0.1:$_serverPort/';
  }

  ServerProvider() {
    _init();
  }

  Future<void> _init() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await WakelockPlus.enable();
        _wakeLockEnabled = true;
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _tabletRole = prefs.getString('tablet_role') ?? 'SERVER';
      _clientServerIp = prefs.getString('client_server_ip') ?? '192.168.43.1';
      _clientServerPort = prefs.getInt('client_server_port') ?? 3000;

      if (_tabletRole == 'SERVER') {
        await startServer(port: _serverPort);
      } else {
        ApiService.instance.setBaseUrl('http://$_clientServerIp:$_clientServerPort');
      }
    } catch (e) {
      print('Error cargando preferencias de ServerProvider: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<bool> configureAsServer({int port = 3000}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tablet_role', 'SERVER');
    _tabletRole = 'SERVER';

    final success = await startServer(port: port);
    notifyListeners();
    return success;
  }

  Future<void> configureAsClient(String ip, {int port = 3000}) async {
    final cleanIp = ip.trim().replaceAll('http://', '').replaceAll('/', '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tablet_role', 'CLIENT');
    await prefs.setString('client_server_ip', cleanIp);
    await prefs.setInt('client_server_port', port);

    if (_isServerRunning) {
      await stopServer();
    }

    _tabletRole = 'CLIENT';
    _clientServerIp = cleanIp;
    _clientServerPort = port;
    ApiService.instance.setBaseUrl('http://$cleanIp:$port');
    notifyListeners();
  }

  Future<String?> discoverServerOnSubnet() async {
    try {
      final info = NetworkInfo();
      String? myIp = await info.getWifiIP();
      if (myIp == null || myIp.isEmpty) {
        for (var interface in await NetworkInterface.list()) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              myIp = addr.address;
              break;
            }
          }
          if (myIp != null) break;
        }
      }

      if (myIp == null || !myIp.contains('.')) return null;

      final parts = myIp.split('.');
      if (parts.length != 4) return null;
      final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

      // 1. Probar IPs estándar / Hotspot primero (192.168.43.1 suele ser el servidor / hotspot)
      final fastCandidates = [
        '$subnet.1',
        '192.168.43.1',
        '$subnet.100',
        '$subnet.50',
        '$subnet.2',
        '$subnet.10',
      ];

      final client = http.Client();
      for (final candidate in fastCandidates) {
        try {
          final res = await client.get(Uri.parse('http://$candidate:3000/api/instancia'))
              .timeout(const Duration(milliseconds: 900));
          if (res.statusCode == 200 && res.body.contains('nombre')) {
            client.close();
            return candidate;
          }
        } catch (_) {}
      }

      // 2. Escaneo paralelo rápido por lotes de 30 IPs
      for (int i = 1; i <= 254; i += 30) {
        final batch = <Future<String?>>[];
        for (int j = i; j < i + 30 && j <= 254; j++) {
          final testIp = '$subnet.$j';
          batch.add(() async {
            try {
              final res = await client.get(Uri.parse('http://$testIp:3000/api/instancia'))
                  .timeout(const Duration(milliseconds: 1400));
              if (res.statusCode == 200 && res.body.contains('nombre')) {
                return testIp;
              }
            } catch (_) {}
            return null;
          }());
        }

        final results = await Future.wait(batch);
        for (final r in results) {
          if (r != null) {
            client.close();
            return r;
          }
        }
      }

      client.close();
    } catch (e) {
      print('Error durante descubrimiento en red: $e');
    }
    return null;
  }

  Future<void> resetConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tablet_role');
    _tabletRole = 'SERVER';
    await startServer(port: _serverPort);
    notifyListeners();
  }

  Future<bool> testConnection(String ip, {int port = 3000}) async {
    try {
      final cleanIp = ip.trim().replaceAll('http://', '').replaceAll('/', '');
      final url = Uri.parse('http://$cleanIp:$port/api/instancia');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startServer({int port = 3000}) async {
    if (kIsWeb) {
      final isAlive = await testConnection('127.0.0.1', port: port);
      _isServerRunning = isAlive;
      _serverPort = port;
      _serverIp = '127.0.0.1';
      ApiService.instance.setBaseUrl('http://127.0.0.1:$_serverPort');
      notifyListeners();
      return isAlive;
    }

    final success = await EmbeddedServer.instance.start(port: port);
    if (success) {
      _isServerRunning = true;
      _serverPort = port;
      _serverIp = EmbeddedServer.instance.localIp ?? '127.0.0.1';
      ApiService.instance.setBaseUrl('http://127.0.0.1:$_serverPort');
      _startMaintenance();
      notifyListeners();
    }
    return success;
  }

  void _startMaintenance() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!_isServerRunning || !isServerRole) {
        timer.cancel();
        return;
      }
      refreshStats();
      if (_wakeLockEnabled && !kIsWeb) {
        try { await WakelockPlus.enable(); } catch (_) {}
      }
    });
  }

  Future<void> stopServer() async {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = null;
    if (!kIsWeb) {
      await EmbeddedServer.instance.stop();
    }
    _isServerRunning = false;
    notifyListeners();
  }

  Future<void> toggleWakeLock(bool enable) async {
    _wakeLockEnabled = enable;
    if (!kIsWeb) {
      if (enable) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    }
    notifyListeners();
  }

  void refreshStats() async {
    if (kIsWeb) {
      final isAlive = await testConnection(_serverIp, port: _serverPort);
      _isServerRunning = isAlive;
      notifyListeners();
      return;
    }
    if (_isServerRunning) {
      _requestCount = EmbeddedServer.instance.requestCount;
      _clientsCount = EmbeddedServer.instance.connectedClientsCount;
      _serverIp = EmbeddedServer.instance.localIp ?? '127.0.0.1';
      notifyListeners();
    }
  }
}
