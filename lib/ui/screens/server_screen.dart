import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/server_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/server_password_dialog.dart';

class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key});

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  late TextEditingController _clientIpController;
  bool _isTestingConnection = false;
  bool _isScanning = false;
  String? _testConnectionResult;
  bool? _testConnectionSuccess;

  @override
  void initState() {
    super.initState();
    final server = context.read<ServerProvider>();
    _clientIpController = TextEditingController(text: server.clientServerIp);
  }

  @override
  void dispose() {
    _clientIpController.dispose();
    super.dispose();
  }

  Future<void> _testConnection(String ip) async {
    setState(() {
      _isTestingConnection = true;
      _testConnectionResult = null;
      _testConnectionSuccess = null;
    });

    final server = context.read<ServerProvider>();
    final ok = await server.testConnection(ip);

    setState(() {
      _isTestingConnection = false;
      _testConnectionSuccess = ok;
      _testConnectionResult = ok
          ? '¡Conexión exitosa con el servidor!'
          : 'No se pudo conectar. Verifica que ambas tablets estén en la misma red WiFi o Hotspot.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerProvider>();
    final isServer = server.isServerRole;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        title: const Text('Configuración de Tablet y Red'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar estadísticas',
            onPressed: () => server.refreshStats(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Selector de Rol: SERVIDOR vs CLIENTE
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16120E),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.borderGlass),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            if (!isServer) {
                              final ok = await ServerPasswordDialog.verify(context);
                              if (!ok) return;
                              await server.configureAsServer();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: isServer ? AppTheme.amberGold : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.dns,
                                  color: isServer ? Colors.black : Colors.white70,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'TABLET SERVIDOR (HOST)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isServer ? Colors.black : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            if (isServer) {
                              await server.configureAsClient(_clientIpController.text.trim());
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: !isServer ? AppTheme.amberGold : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.tablet_android,
                                  color: !isServer ? Colors.black : Colors.white70,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'MODO CLIENTE (TERMINAL / IPHONE)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: !isServer ? Colors.black : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Contenido dinámico según el Rol
                if (isServer) ...[
                  // MODO SERVIDOR
                  GlassCard(
                    borderRadius: 22,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: server.isServerRunning
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.red.withOpacity(0.2),
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
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: server.isServerRunning ? Colors.greenAccent : Colors.redAccent,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Esta tablet aloja la base de datos pos_evento.db y atiende a las demás tablets.',
                                    style: TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: server.isServerRunning,
                              activeColor: Colors.greenAccent,
                              onChanged: (val) async {
                                if (val) {
                                  final ok = await server.startServer();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(ok
                                            ? '✅ Servidor local en línea (puerto ${server.serverPort}).'
                                            : '❌ No se pudo encender el servidor en el puerto ${server.serverPort}.'),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                } else {
                                  await server.stopServer();
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        const Divider(color: AppTheme.borderGlass),
                        const SizedBox(height: 16),

                        // Métricas del Servidor
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricTile(
                                'IP LOCAL (WIFI)',
                                server.serverIp,
                                Icons.wifi,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricTile(
                                'PUERTO',
                                server.serverPort.toString(),
                                Icons.numbers,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricTile(
                                'TABLETS CONECTADAS',
                                '${server.clientsCount}',
                                Icons.devices,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricTile(
                                'PETICIONES ATENDIDAS',
                                '${server.requestCount}',
                                Icons.speed,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // URL para que los clientes se conecten
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.amberGold.withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'IP PARA LAS DEMÁS TABLETS:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.amberGold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18, color: AppTheme.amberGold),
                                    tooltip: 'Copiar IP',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: server.serverIp));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('IP copiada al portapapeles')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              SelectableText(
                                server.serverIp,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Escribe esta IP en las tablets que estén en Modo Cliente',
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // MODO CLIENTE
                  GlassCard(
                    borderRadius: 22,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.tablet_android, color: AppTheme.amberGold, size: 28),
                            SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DISPOSITIVO EN MODO CLIENTE',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Conecta este iPhone o tablet a la tablet Samsung que corre el servidor',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const Divider(color: AppTheme.borderGlass),
                        const SizedBox(height: 18),

                        const Text(
                          'IP de la Tablet Servidor:',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _clientIpController,
                          keyboardType: TextInputType.text,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: 'Ej. 192.168.43.1',
                            hintStyle: const TextStyle(color: Colors.white38),
                            prefixIcon: const Icon(Icons.wifi, color: AppTheme.amberGold),
                            filled: true,
                            fillColor: const Color(0xFF1B1612),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppTheme.borderGlass),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppTheme.borderGlass),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppTheme.amberGold, width: 2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        OutlinedButton.icon(
                          onPressed: _isScanning
                              ? null
                              : () async {
                                  setState(() {
                                    _isScanning = true;
                                    _testConnectionResult = null;
                                  });
                                  final foundIp = await server.discoverServerOnSubnet();
                                  setState(() {
                                    _isScanning = false;
                                  });
                                  if (foundIp != null) {
                                    _clientIpController.text = foundIp;
                                    setState(() {
                                      _testConnectionSuccess = true;
                                      _testConnectionResult = '¡Servidor MasterDrinks detectado en $foundIp!';
                                    });
                                  } else {
                                    setState(() {
                                      _testConnectionSuccess = false;
                                      _testConnectionResult = 'No se detectó un servidor activo en esta subred. Verifica que el servidor esté encendido o escribe la IP manualmente.';
                                    });
                                  }
                                },
                          icon: _isScanning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amberGold),
                                )
                              : const Icon(Icons.radar, color: AppTheme.amberGold),
                          label: Text(
                            _isScanning ? 'Escaneando subred Wi-Fi...' : '🔍 AUTO-DETECTAR SERVIDOR EN WI-FI',
                            style: const TextStyle(color: AppTheme.amberGold, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.amberGold),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isTestingConnection
                                    ? null
                                    : () => _testConnection(_clientIpController.text.trim()),
                                icon: _isTestingConnection
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amberGold),
                                      )
                                    : const Icon(Icons.network_check, color: AppTheme.amberGold),
                                label: Text(
                                  _isTestingConnection ? 'Probando...' : 'PROBAR CONEXIÓN',
                                  style: const TextStyle(color: AppTheme.amberGold, fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.amberGold),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final ip = _clientIpController.text.trim();
                                  await server.configureAsClient(ip);
                                  if (mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                                icon: const Icon(Icons.check_circle, color: Colors.black),
                                label: const Text(
                                  'GUARDAR Y CONECTAR',
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.amberGold,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (_testConnectionResult != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: (_testConnectionSuccess == true)
                                  ? Colors.green.withOpacity(0.15)
                                  : Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: (_testConnectionSuccess == true) ? Colors.greenAccent : Colors.redAccent,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  (_testConnectionSuccess == true) ? Icons.check_circle : Icons.error_outline,
                                  color: (_testConnectionSuccess == true) ? Colors.greenAccent : Colors.redAccent,
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _testConnectionResult!,
                                    style: TextStyle(
                                      color: (_testConnectionSuccess == true) ? Colors.greenAccent : Colors.redAccent,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Mantener Pantalla Encendida
                GlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.screen_lock_portrait, color: AppTheme.amberGold, size: 22),
                          SizedBox(width: 12),
                          Text(
                            'Mantener pantalla encendida (Wakelock)',
                            style: TextStyle(fontSize: 14, color: Colors.white),
                          ),
                        ],
                      ),
                      Switch(
                        value: server.wakeLockEnabled,
                        activeColor: AppTheme.amberGold,
                        onChanged: (val) => server.toggleWakeLock(val),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Botón Principal para volver al POS
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.point_of_sale, color: Colors.black, size: 22),
                  label: const Text(
                    'VOLVER AL SISTEMA POS',
                    style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amberGold,
                    padding: const EdgeInsets.symmetric(vertical: 18),
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

  Widget _buildMetricTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1612),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderGlass),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.amberGold, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
