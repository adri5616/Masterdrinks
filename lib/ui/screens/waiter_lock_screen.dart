import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pos_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/number_pad.dart';
import 'admin/admin_main_screen.dart';

class WaiterLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const WaiterLockScreen({
    super.key,
    required this.onUnlocked,
  });

  @override
  State<WaiterLockScreen> createState() => _WaiterLockScreenState();
}

class _WaiterLockScreenState extends State<WaiterLockScreen> {
  String _pin = '';
  String? _error;

  void _onDigitTap(String digit) {
    if (_pin.length < 6) {
      setState(() {
        _pin += digit;
        _error = null;
      });
      if (_pin.length == 4) {
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
    final auth = context.read<AuthProvider>();

    // Atajo para acceso como Administrador: PIN 0000 o clave de admin
    if (_pin == '0000' || _pin == 'admin*12345') {
      final adminOk = await auth.loginAdminPin(_pin);
      if (adminOk && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AdminMainScreen()),
        );
        setState(() {
          _pin = '';
        });
        return;
      }
    }

    final ok = await auth.unlockWaiter(_pin);
    if (ok && mounted) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = auth.errorMessage ?? 'PIN incorrecto';
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pos = context.watch<PosProvider>();
    final config = pos.eventConfig;

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.92),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: GlassCard(
              borderRadius: 24,
              padding: const EdgeInsets.all(0),
              child: Row(
                children: [
                  // Lado izquierdo: Afiche del evento
                  Expanded(
                    flex: 5,
                    child: Container(
                      height: 520,
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                            child: Image.asset(
                              'assets/web/afiche/jesseyjoy.jpg',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset(
                                'assets/web/Wallpaper.jpg',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFF1B140F),
                                  child: const Center(
                                    child: Icon(Icons.music_note, size: 80, color: AppTheme.amberGold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Overlay con datos del evento
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.85),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  config?.evento ?? 'Festival Sonidos de Verano 2026',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${config?.barra ?? "Barra 1"} · ${config?.lugar ?? "Estadio Central"}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.amberGold,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Lado derecho: Teclado de PIN de Mesero
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.pin, color: AppTheme.amberGold, size: 36),
                          const SizedBox(height: 10),
                          const Text(
                            'CLAVE DE MESERO',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ingresa tu PIN de 4 dígitos para vender',
                            style: TextStyle(fontSize: 12, color: Colors.white60),
                          ),
                          const SizedBox(height: 16),

                          // Visualizador de PIN (Puntos)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              final filled = index < _pin.length;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: filled ? AppTheme.amberGold : Colors.transparent,
                                  border: Border.all(
                                    color: filled ? AppTheme.amberGold : Colors.white38,
                                    width: 2,
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 10),

                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                              ),
                            ),

                          // Teclado Numérico
                          NumberPad(
                            onDigitTap: _onDigitTap,
                            onClear: _onClear,
                            onDelete: _onDelete,
                          ),
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
}
