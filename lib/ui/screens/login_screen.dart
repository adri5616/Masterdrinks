import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/pos_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/number_pad.dart';
import 'pos_screen.dart';
import 'server_screen.dart';
import 'admin/admin_main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuarioController = TextEditingController(text: 'adri');
  final _passwordController = TextEditingController(text: '1234');
  bool _isAdminMode = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _switchRole(bool isAdmin) {
    setState(() {
      _isAdminMode = isAdmin;
      if (isAdmin) {
        _usuarioController.text = 'admin';
        _passwordController.text = 'admin*12345';
      } else {
        _usuarioController.text = 'adri';
        _passwordController.text = '1234';
      }
    });
  }

  Future<void> _handleLogin() async {
    final auth = context.read<AuthProvider>();
    final server = context.read<ServerProvider>();

    if (server.isServerRole && !server.isServerRunning) {
      await server.startServer();
    }

    final success = await auth.login(
      _usuarioController.text.trim(),
      _passwordController.text,
    );

    if (success && mounted) {
      context.read<PosProvider>().loadCatalog();

      if (auth.isAdmin) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AdminMainScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PosScreen()),
        );
      }
    }
  }

  void _openPinOrFaceIdModal() {
    showDialog(
      context: context,
      builder: (ctx) => _PinAccessDialog(
        onSuccess: () {
          Navigator.of(ctx).pop();
          context.read<PosProvider>().loadCatalog();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminMainScreen()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final server = context.watch<ServerProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // Fondo decorativo con gradiente oscuro
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.7, -0.4),
                radius: 1.2,
                colors: [
                  Color(0xFF2A1608),
                  Color(0xFF0F0B08),
                  Color(0xFF070504),
                ],
              ),
            ),
          ),

          // Botón superior de estado de red / Servidor
          Positioned(
            top: 24,
            right: 24,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ServerScreen()),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: server.isServerRole
                        ? Colors.greenAccent
                        : (server.isClientRole ? AppTheme.amberGold : Colors.white38),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      server.isServerRole ? Icons.dns : Icons.tablet_android,
                      size: 16,
                      color: server.isServerRole ? Colors.greenAccent : AppTheme.amberGold,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      server.isServerRole
                          ? (server.isServerRunning ? 'SERVIDOR: ${server.serverIp}' : 'SERVIDOR DETENIDO')
                          : 'CLIENTE (A: ${server.clientServerIp})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: server.isServerRole ? Colors.greenAccent : AppTheme.amberGold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.settings, size: 14, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ),

          // Contenedor Central de Login
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: GlassCard(
                  borderRadius: 24,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo y Título
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.amberGold.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.amberGold, width: 2),
                          ),
                          child: const Icon(
                            Icons.sports_bar,
                            color: AppTheme.amberGold,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'MASTERDRINKS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.amberGold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Punto de Venta de Eventos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white54,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Selector de Rol (Cajero / Administrador)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.borderGlass),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _switchRole(false),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: !_isAdminMode ? AppTheme.amberGold : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'CAJERO',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: !_isAdminMode ? Colors.black : Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () => _switchRole(true),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _isAdminMode ? AppTheme.amberGold : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'ADMINISTRADOR',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: _isAdminMode ? Colors.black : Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Campo Usuario
                      TextField(
                        controller: _usuarioController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Usuario',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.person_outline, color: AppTheme.amberGold),
                          filled: true,
                          fillColor: AppTheme.surfaceGlass,
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
                      const SizedBox(height: 14),

                      // Campo Contraseña
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          labelStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.amberGold),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              color: Colors.white54,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          filled: true,
                          fillColor: AppTheme.surfaceGlass,
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
                        onSubmitted: (_) => _handleLogin(),
                      ),
                      const SizedBox(height: 12),

                      // Mensaje de Error
                      if (auth.errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            auth.errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),

                      const SizedBox(height: 8),

                      // Botón Iniciar Sesión
                      ElevatedButton(
                        onPressed: auth.isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppTheme.amberGold,
                          foregroundColor: Colors.black,
                          elevation: 6,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: auth.isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : const Text(
                                'INGRESAR AL SISTEMA',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),

                      // Botón Acceso Rápido con PIN o Face ID
                      OutlinedButton.icon(
                        onPressed: _openPinOrFaceIdModal,
                        icon: const Icon(Icons.camera_alt_outlined, color: AppTheme.amberGold, size: 18),
                        label: const Text(
                          'ACCESO CON PIN / FACE ID (0000)',
                          style: TextStyle(color: AppTheme.amberGold, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.amberGold.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinAccessDialog extends StatefulWidget {
  final VoidCallback onSuccess;

  const _PinAccessDialog({required this.onSuccess});

  @override
  State<_PinAccessDialog> createState() => _PinAccessDialogState();
}

class _PinAccessDialogState extends State<_PinAccessDialog> {
  String _pin = '';
  String? _error;
  bool _isLoading = false;

  void _onDigitTap(String digit) {
    if (_pin.length < 8) {
      setState(() {
        _pin += digit;
        _error = null;
      });
      if (_pin == '0000' || _pin == 'admin*12345') {
        _submitPin();
      }
    }
  }

  void _onClear() {
    setState(() {
      _pin = '';
      _error = null;
    });
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _error = null;
      });
    }
  }

  Future<void> _submitPin() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();

    // Si escribe el PIN o contraseña de administrador
    final ok = await auth.loginAdminPin(_pin);
    if (ok) {
      widget.onSuccess();
    } else {
      setState(() {
        _isLoading = false;
        _error = auth.errorMessage ?? 'PIN incorrecto';
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16120E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_clock, color: AppTheme.amberGold, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'PIN / Face ID Admin',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Ingresa tu clave de administrador o 0000 para acceso biométrico:',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Visor de PIN
            Container(
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderGlass),
              ),
              child: Text(
                _pin.isEmpty ? '••••' : '•' * _pin.length,
                style: const TextStyle(
                  color: AppTheme.amberGold,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],

            const SizedBox(height: 16),

            // Teclado Numérico
            NumberPad(
              onDigitTap: _onDigitTap,
              onClear: _onClear,
              onDelete: _onDelete,
            ),
            const SizedBox(height: 14),

            ElevatedButton(
              onPressed: _isLoading || _pin.isEmpty ? null : _submitPin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amberGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Text('VERIFICAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
