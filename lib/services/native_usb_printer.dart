import 'dart:convert';
import 'package:flutter/services.dart';

class NativeUsbPrinter {
  static const MethodChannel _channel = MethodChannel('com.masterdrinks/usb_printer');

  /// Devuelve la lista de dispositivos USB conectados
  static Future<List<Map<String, dynamic>>> getDevices() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('getUsbDevices');
      if (res == null) return [];
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Envía los bytes ESC/POS directamente a la impresora USB
  static Future<Map<String, dynamic>> printBytes(List<int> bytes, {int? deviceId}) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('printBytes', {
        'bytes': Uint8List.fromList(bytes),
        'deviceId': deviceId,
      });
      return {
        'success': true,
        'bytesWritten': res?['bytesWritten'] ?? bytes.length,
      };
    } on PlatformException catch (e) {
      return {
        'success': false,
        'code': e.code,
        'error': e.message ?? e.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'code': 'UNKNOWN',
        'error': e.toString(),
      };
    }
  }

  /// Solicita explícitamente permiso USB para un dispositivo
  static Future<bool> requestPermission({int? deviceId}) async {
    try {
      final res = await _channel.invokeMethod<bool>('requestUsbPermission', {
        'deviceId': deviceId,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}
