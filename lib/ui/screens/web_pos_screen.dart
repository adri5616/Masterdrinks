import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../config/theme.dart';
import '../../providers/server_provider.dart';
import '../../services/native_usb_printer.dart';
import '../widgets/server_password_dialog.dart';
import 'server_screen.dart';

class WebPosScreen extends StatefulWidget {
  const WebPosScreen({super.key});

  @override
  State<WebPosScreen> createState() => _WebPosScreenState();
}

class _WebPosScreenState extends State<WebPosScreen> {
  WebViewController? _webViewController;
  String? _currentLoadedUrl;
  bool _isLoadingWeb = true;
  bool _isInitializing = false;
  final TextEditingController _clientIpInputController = TextEditingController(text: '192.168.43.1');

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _clientIpInputController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await [
          Permission.camera,
          Permission.microphone,
        ].request();
      } catch (e) {
        print('Error solicitando permisos de cámara: $e');
      }
    }
  }

  Future<void> _initializeWebView(String targetUrl) async {
    if ((_currentLoadedUrl == targetUrl && _webViewController != null) || _isInitializing) {
      return;
    }

    _isInitializing = true;
    _currentLoadedUrl = targetUrl;

    if (mounted) {
      setState(() {
        _isLoadingWeb = true;
      });
    }

    try {
      // Si carga en servidor local y no está activo, esperar brevemente a que responda
      if (targetUrl.contains('127.0.0.1') || targetUrl.contains('localhost')) {
        final server = context.read<ServerProvider>();
        if (!server.isServerRunning) {
          final client = http.Client();
          for (int i = 0; i < 20; i++) {
            try {
              final res = await client.get(Uri.parse('http://127.0.0.1:3000/api/instancia'))
                  .timeout(const Duration(milliseconds: 150));
              if (res.statusCode == 200) break;
            } catch (_) {}
            await Future.delayed(const Duration(milliseconds: 100));
          }
          client.close();
        }
      }

      final controller = WebViewController();
      controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      controller.setBackgroundColor(const Color(0xFF0A0A0F));

      if (!kIsWeb && Platform.isAndroid && controller.platform is AndroidWebViewController) {
        AndroidWebViewController.enableDebugging(kDebugMode);
        final androidController = controller.platform as AndroidWebViewController;
        androidController.setMediaPlaybackRequiresUserGesture(false);
        androidController.setOnPlatformPermissionRequest((request) {
          request.grant();
        });
      }

      controller.setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoadingWeb = true;
              });
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoadingWeb = false;
              });
              final server = context.read<ServerProvider>();
              final info = {
                'role': server.tabletRole,
                'serverIp': server.clientServerIp,
                'localIp': server.serverIp,
                'isServer': server.isServerRole,
              };
              controller.runJavaScript("if (window.onMasterDrinksNativeInfo) window.onMasterDrinksNativeInfo(${jsonEncode(info)});");
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('rawbt:') || request.url.startsWith('intent:')) {
              try {
                launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
              } catch (e) {
                print('Error al lanzar URI de impresión: $e');
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

      // Canal de comunicación JavaScript <-> Flutter
      controller.addJavaScriptChannel(
        'MasterDrinksNative',
        onMessageReceived: (JavaScriptMessage message) async {
          try {
            final data = jsonDecode(message.message);
            final action = data['action'] ?? data['type'];
            final server = context.read<ServerProvider>();

            if (action == 'native_usb_print' || action == 'print_native_usb') {
              final base64Data = data['base64']?.toString() ?? '';
              final deviceId = data['deviceId'] as int?;
              final callback = data['callback']?.toString() ?? 'window.onNativeUsbPrintResult';
              if (base64Data.isNotEmpty) {
                try {
                  final bytes = base64Decode(base64Data);
                  final res = await NativeUsbPrinter.printBytes(bytes, deviceId: deviceId);
                  controller.runJavaScript("if (typeof $callback === 'function') $callback(${jsonEncode(res)});");
                } catch (e) {
                  controller.runJavaScript("if (typeof $callback === 'function') $callback(${jsonEncode({'success': false, 'error': e.toString()})});");
                }
              } else {
                controller.runJavaScript("if (typeof $callback === 'function') $callback(${jsonEncode({'success': false, 'error': 'No data'})});");
              }
            } else if (action == 'get_usb_devices') {
              final devices = await NativeUsbPrinter.getDevices();
              final callback = data['callback']?.toString() ?? 'window.onUsbDevicesResult';
              controller.runJavaScript("if (typeof $callback === 'function') $callback(${jsonEncode(devices)});");
            } else if (action == 'request_usb_permission') {
              final deviceId = data['deviceId'] as int?;
              final granted = await NativeUsbPrinter.requestPermission(deviceId: deviceId);
              final callback = data['callback']?.toString() ?? 'window.onUsbPermissionResult';
              controller.runJavaScript("if (typeof $callback === 'function') $callback(${jsonEncode({'granted': granted})});");
            } else if (action == 'rawbt_print' || action == 'print_rawbt') {
              final url = data['url']?.toString();
              if (url != null && url.isNotEmpty) {
                try {
                  final uri = Uri.parse(url);
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  print('Error al lanzar RawBT desde bridge: $e');
                }
              }
            } else if (action == 'get_network_info') {
              final info = {
                'role': server.tabletRole,
                'serverIp': server.clientServerIp,
                'localIp': server.serverIp,
                'isServer': server.isServerRole,
              };
              controller.runJavaScript("if (window.onMasterDrinksNativeInfo) window.onMasterDrinksNativeInfo(${jsonEncode(info)});");
            } else if (action == 'set_role') {
              final role = data['role'];
              if (role == 'SERVER') {
                await server.configureAsServer();
              } else if (role == 'CLIENT') {
                final ip = (data['ip'] ?? server.clientServerIp).toString();
                await server.configureAsClient(ip);
              }
              final newUrl = server.effectiveWebUrl;
              _initializeWebView(newUrl);
            } else if (action == 'scan_network') {
              final foundIp = await server.discoverServerOnSubnet();
              final res = {'found': foundIp != null, 'ip': foundIp};
              controller.runJavaScript("if (window.onMasterDrinksScanResult) window.onMasterDrinksScanResult(${jsonEncode(res)});");
            } else if (action == 'open_settings') {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerScreen()),
              ).then((_) {
                final updatedUrl = server.effectiveWebUrl;
                if (_currentLoadedUrl != updatedUrl) {
                  _initializeWebView(updatedUrl);
                }
              });
            }
          } catch (e) {
            print('Error en bridge MasterDrinksNative: $e');
          }
        },
      );

      await controller.loadRequest(Uri.parse(targetUrl));

      if (mounted) {
        setState(() {
          _webViewController = controller;
        });
      }
    } finally {
      _isInitializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerProvider>();
    final isAndroid = !kIsWeb && Platform.isAndroid;

    // 1. Cargando preferencias iniciales
    if (!server.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.amberGold),
        ),
      );
    }

    if (!server.isConfigured) {
      return _buildInitialSetupScreen(server);
    }

    // 2. Tablet configurada: cargar WebView con la URL correspondiente
    final targetUrl = server.effectiveWebUrl;
    if (isAndroid && (_webViewController == null || _currentLoadedUrl != targetUrl)) {
      _initializeWebView(targetUrl);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Stack(
          children: [
            // Vista Web (POS Nativo)
            if (isAndroid && _webViewController != null) ...[
              Positioned.fill(
                child: WebViewWidget(
                  controller: _webViewController!,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                ),
              ),
              if (_isLoadingWeb)
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFF0A0A0F),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppTheme.amberGold),
                          SizedBox(height: 16),
                          Text(
                            'Cargando MasterDrinks POS...',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ] else ...[
              // Vista en Windows Desktop para pruebas y control
              Positioned.fill(
                child: _buildDesktopDashboard(server),
              ),
            ],

            // Botón flotante discreto de configuración para cambiar de IP o rol
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () async {
                    final ok = await ServerPasswordDialog.verify(context);
                    if (!ok) return;
                    if (!mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServerScreen()),
                    ).then((_) {
                      final updatedUrl = server.effectiveWebUrl;
                      if (_currentLoadedUrl != updatedUrl) {
                        _initializeWebView(updatedUrl);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.amberGold.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          server.isServerRole ? Icons.dns : Icons.tablet_android,
                          size: 16,
                          color: AppTheme.amberGold,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          server.isServerRole ? 'SERVIDOR' : 'CLIENTE',
                          style: const TextStyle(
                            color: AppTheme.amberGold,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.settings, size: 14, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pantalla de configuración inicial si nunca se ha elegido el rol
  Widget _buildInitialSetupScreen(ServerProvider server) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF16120E),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.borderGlass),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppTheme.amberGold.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.amberGold, width: 2),
                      ),
                      child: const Icon(Icons.sports_bar, color: AppTheme.amberGold, size: 36),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'MASTERDRINKS POS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.amberGold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Selecciona cómo vas a utilizar esta tablet:',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  // OPCION A: SERVIDOR
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      final ok = await ServerPasswordDialog.verify(context);
                      if (!ok) return;
                      await server.configureAsServer();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF221C16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.amberGold.withOpacity(0.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppTheme.amberGold.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.dns, color: AppTheme.amberGold, size: 28),
                          ),
                          const SizedBox(width: 18),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TABLET SERVIDOR (HOST)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Esta tablet tiene la base de datos principal y aloja el sistema para todas las tablets.',
                                  style: TextStyle(color: Colors.white60, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, color: AppTheme.amberGold, size: 18),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // OPCION B: CLIENTE
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      _showClientConfigDialog(server);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF221C16),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.borderGlass),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.tablet_android, color: Colors.white70, size: 28),
                          ),
                          const SizedBox(width: 18),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TABLET TERMINAL (CLIENTE)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Esta tablet se conecta por Wi-Fi a la tablet servidor para registrar ventas.',
                                  style: TextStyle(color: Colors.white60, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showClientConfigDialog(ServerProvider server) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16120E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Conectar a Servidor', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa la IP de la tablet servidor (la puedes ver en la pantalla de la tablet servidor):',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _clientIpInputController,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Ej. 192.168.43.1',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.wifi, color: AppTheme.amberGold),
                filled: true,
                fillColor: const Color(0xFF221C16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = _clientIpInputController.text.trim();
              if (ip.isNotEmpty) {
                Navigator.of(ctx).pop();
                await server.configureAsClient(ip);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amberGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('Conectar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Dashboard de control para Windows Desktop
  Widget _buildDesktopDashboard(ServerProvider server) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF16120E),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.borderGlass),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: server.isServerRunning ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                        border: Border.all(
                          color: server.isServerRunning ? Colors.greenAccent : Colors.redAccent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.dns,
                        color: server.isServerRunning ? Colors.greenAccent : Colors.redAccent,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            server.isServerRunning ? 'SERVIDOR EN LÍNEA' : 'SERVIDOR DETENIDO',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: server.isServerRunning ? Colors.greenAccent : Colors.redAccent,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'http://${server.serverIp}:${server.serverPort}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(color: AppTheme.borderGlass),
                const SizedBox(height: 16),
                const Text(
                  'El servidor está corriendo nativamente en esta aplicación (sin necesidad de Termux).\n'
                  'Todas las tablets y terminales conectadas consumen la base de datos real con Face ID.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    launchUrl(
                      Uri.parse(server.effectiveWebUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.open_in_browser, size: 22),
                  label: const Text(
                    'PROBAR SISTEMA POS EN NAVEGADOR',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amberGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await ServerPasswordDialog.verify(context);
                    if (!ok) return;
                    if (!mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServerScreen()),
                    );
                  },
                  icon: const Icon(Icons.settings, color: Colors.white70),
                  label: const Text(
                    'AJUSTES DE RED Y CLIENTES',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.borderGlass),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
