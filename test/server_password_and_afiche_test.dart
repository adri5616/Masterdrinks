import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:masterdrinks/ui/widgets/server_password_dialog.dart';

void main() {
  group('MasterDrinks Server Security & Afiche Assets Tests', () {
    test('1. Contraseña del servidor debe ser exactamente 561601 y hardcodeada', () {
      expect(ServerPasswordDialog.serverPassword, equals('561601'));
    });

    test('2. Afiches del evento deben existir en disco para empaquetado en APK', () {
      final aficheFile = File('assets/web/afiche/jessy_y_joy.jpg');
      expect(aficheFile.existsSync(), isTrue, reason: 'El cartel oficial jessy_y_joy.jpg debe existir en assets/web/afiche/');
      expect(aficheFile.lengthSync(), greaterThan(1000), reason: 'El archivo debe tener contenido real');

      final altJesse = File('assets/web/afiche/jesse.jpg');
      expect(altJesse.existsSync(), isTrue, reason: 'jesse.jpg alternativo debe existir');

      final altGemini = File('assets/web/afiche/gemini_generated_image_3p17o13p17o13p17.jpg');
      expect(altGemini.existsSync(), isTrue, reason: 'gemini banner alternativo debe existir');

      final altGpt = File('assets/web/afiche/chatgpt_image_11_sept_2026__02_55_36_p_m_.png');
      expect(altGpt.existsSync(), isTrue, reason: 'chatgpt banner alternativo debe existir');
    });

    test('3. Pubspec incluye assets/web/afiche/', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('assets/web/afiche/'), isTrue, reason: 'pubspec.yaml debe registrar assets/web/afiche/');
    });
  });
}
