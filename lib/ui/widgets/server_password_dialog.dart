import 'package:flutter/material.dart';
import '../../config/theme.dart';

class ServerPasswordDialog {
  /// Contraseña hardcodeada de seguridad para acceder o configurar el servidor (sin necesidad de BD)
  static const String serverPassword = '561601';

  /// Muestra un diálogo solicitando la contraseña del servidor.
  /// Retorna `true` únicamente si se ingresó '561601'.
  static Future<bool> verify(BuildContext context) async {
    final controller = TextEditingController();
    bool obscure = true;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              final input = controller.text.trim();
              if (input == serverPassword) {
                Navigator.of(ctx).pop(true);
              } else {
                setState(() {
                  errorText = 'Contraseña incorrecta';
                });
              }
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF16120E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppTheme.amberGold.withOpacity(0.5), width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.amberGold.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_outline, color: AppTheme.amberGold, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Acceso al Servidor',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ingresa la contraseña de seguridad para configurar o gestionar el Servidor Host:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    obscureText: obscure,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      letterSpacing: 4.0,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'PIN / Clave',
                      hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 1.0, fontSize: 14),
                      errorText: errorText,
                      errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      filled: true,
                      fillColor: const Color(0xFF221C16),
                      prefixIcon: const Icon(Icons.vpn_key, color: AppTheme.amberGold),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white54,
                        ),
                        onPressed: () {
                          setState(() {
                            obscure = !obscure;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppTheme.borderGlass),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.amberGold, width: 2),
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amberGold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  ),
                  child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result ?? false;
  }
}
