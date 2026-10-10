import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/database/database_helper.dart';
import 'web_assets_helper.dart';

/// FIFO Async Mutex para serializar transacciones de escritura con timeout de seguridad.
/// Garantiza que solicitudes concurrentes de múltiples cajeros/meseros
/// nunca provoquen errores de "database is locked (code 5)" en SQLite ni bloqueos mutuos.
class AsyncMutex {
  Future<void>? _last;

  Future<T> run<T>(Future<T> Function() action, {Duration timeout = const Duration(seconds: 15)}) {
    final prev = _last;
    final completer = Completer<void>();
    _last = completer.future;
    return Future.sync(() async {
      if (prev != null) {
        try {
          await prev.timeout(timeout);
        } catch (_) {}
      }
      return await action().timeout(timeout);
    }).whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }
}

/// Cache en memoria L1 de ultra alta velocidad (< 0.2ms) para endpoints de lectura frecuente.
class L1Cache {
  static String? instanciaJson;
  static String? configuracionJson;
  static String? productosJson;
  static String? stockJson;
  static String? personalJson;

  static void clear() {
    instanciaJson = null;
    configuracionJson = null;
    productosJson = null;
    stockJson = null;
    personalJson = null;
  }

  static void invalidateStock() {
    productosJson = null;
    stockJson = null;
  }

  static void invalidateConfig() {
    instanciaJson = null;
    configuracionJson = null;
  }

  static void invalidatePersonal() {
    personalJson = null;
  }

  static void invalidateCatalog() {
    productosJson = null;
    stockJson = null;
  }
}

class EmbeddedServer {
  static final EmbeddedServer instance = EmbeddedServer._();
  EmbeddedServer._();

  HttpServer? _server;
  int _port = 3000;
  String? _localIp;
  int _requestCount = 0;
  final Set<String> _connectedClients = {};

  // Conexión cacheada a la base de datos para máxima velocidad
  Database? _cachedDb;

  // Cache en memoria para imágenes decodificadas de productos y promociones
  final Map<String, (String, Uint8List)> _fotoCache = {};

  // Afiche activo en RAM para el modal de PIN y branding del evento
  Uint8List? _customAficheBytes;
  String _customAficheMime = 'image/jpeg';
  String _customAficheNombre = 'jessy_y_joy.jpg';

  // Mutex transaccional para escrituras serializadas
  final AsyncMutex _writeMutex = AsyncMutex();

  // Watchdog de autorreparación continua para que el servidor nunca se caiga
  Timer? _watchdogTimer;
  bool _shouldBeRunning = false;

  /// Reparte el precio de un paquete/promo entre sus componentes proporcionalmente a su precio de catálogo
  static List<Map<String, dynamic>> _repartirPrecioPaquete(List<Map<String, dynamic>> partes, double precioPaquete) {
    if (partes.isEmpty) return [];

    final suelto = double.parse(partes.fold<double>(0.0, (sum, p) =>
      sum + ((p['precioCatalogo'] as num).toDouble()) * ((p['qty'] as num).toDouble())).toStringAsFixed(2));

    final List<Map<String, dynamic>> lineas;
    if (suelto > 0) {
      final factor = precioPaquete / suelto;
      lineas = partes.map((p) {
        final precio = double.parse((((p['precioCatalogo'] as num).toDouble()) * factor).toStringAsFixed(2));
        final qty = (p['qty'] as num).toDouble();
        final subtotal = double.parse((precio * qty).toStringAsFixed(2));
        return {
          'idProd': p['idProd'],
          'qty': p['qty'],
          'precio': precio,
          'subtotal': subtotal,
          'nombre': p['nombre'],
        };
      }).toList();
    } else {
      // Si los productos no tienen precio definido en catálogo, repartir equitativamente
      final subtotalUnitario = double.parse((precioPaquete / partes.length).toStringAsFixed(2));
      lineas = partes.map((p) {
        final qty = (p['qty'] as num).toDouble();
        final precio = qty > 0 ? double.parse((subtotalUnitario / qty).toStringAsFixed(2)) : subtotalUnitario;
        return {
          'idProd': p['idProd'],
          'qty': p['qty'],
          'precio': precio,
          'subtotal': subtotalUnitario,
          'nombre': p['nombre'],
        };
      }).toList();
    }

    // Cuadre exacto al centavo con el precio cerrado del combo
    final sumado = double.parse(lineas.fold<double>(0.0, (sum, l) => sum + ((l['subtotal'] as num).toDouble())).toStringAsFixed(2));
    final sobra = double.parse((precioPaquete - sumado).toStringAsFixed(2));
    if (sobra != 0.0 && lineas.isNotEmpty) {
      int masCara = 0;
      for (int i = 1; i < lineas.length; i++) {
        if (((lineas[i]['subtotal'] as num).toDouble()) > ((lineas[masCara]['subtotal'] as num).toDouble())) {
          masCara = i;
        }
      }
      final nuevoSubtotal = double.parse((((lineas[masCara]['subtotal'] as num).toDouble()) + sobra).toStringAsFixed(2));
      lineas[masCara]['subtotal'] = nuevoSubtotal;
      final qty = ((lineas[masCara]['qty'] as num).toDouble());
      if (qty > 0) {
        lineas[masCara]['precio'] = double.parse((nuevoSubtotal / qty).toStringAsFixed(2));
      }
    }
    return lineas;
  }

  /// Ejecuta la anulación completa de una comanda restituyendo stock al inventario y registrando auditoría
  Future<Response> _ejecutarAnulacionComanda({
    required int idComanda,
    required int idAdmin,
    required String motivo,
  }) async {
    final db = await _getDb();
    final now = DatabaseHelper.nowSql();

    return await _withTransaction((txn) async {
      final comRow = await txn.rawQuery(
        'SELECT id_comanda, id_evento, estado_pago, estatus FROM comanda WHERE id_comanda = ?',
        [idComanda],
      );
      if (comRow.isEmpty) {
        return _error('Comanda #$idComanda no encontrada', statusCode: 404);
      }
      final estadoPago = comRow.first['estado_pago']?.toString().toUpperCase();
      final estatus = comRow.first['estatus']?.toString().toUpperCase();
      if (estadoPago == 'ANULADO' || estatus == 'CANCELADA') {
        return _error('Esta comanda ya estaba anulada', statusCode: 400);
      }

      final idEvento = comRow.first['id_evento'] ?? 1;

      // 1. Actualizar comanda a CANCELADA y ANULADO
      await txn.rawUpdate('''
        UPDATE comanda
        SET estatus = 'CANCELADA', estado_pago = 'ANULADO',
            motivo_anulacion = ?, fecha_anulacion = ?, anulada_por_admin = ?
        WHERE id_comanda = ?
      ''', [motivo, now, idAdmin, idComanda]);

      // 2. Anular pagos asociados
      await txn.rawUpdate("UPDATE pago_comanda SET estado = 'ANULADO' WHERE id_comanda = ?", [idComanda]);

      // 3. Devolución de stock exacta para todos los productos de la comanda (regulares, combos y acompañantes)
      final detalles = await txn.rawQuery('''
        SELECT id_producto, cantidad, id_promocion FROM detalle_comanda WHERE id_comanda = ? AND id_producto IS NOT NULL
      ''', [idComanda]);

      for (var d in detalles) {
        final idProd = d['id_producto'] as int?;
        final qty = (d['cantidad'] is num) ? (d['cantidad'] as num).toDouble() : 0.0;
        if (idProd == null || qty <= 0) continue;

        final pRow = await txn.rawQuery('''
          SELECT id_producto, stock_actual, id_categoria, id_botella_vinculada, vasos_por_botella, nombre
          FROM producto WHERE id_producto = ?
        ''', [idProd]);

        if (pRow.isNotEmpty) {
          final pData = pRow.first;
          final idBotella = pData['id_botella_vinculada'] as int?;
          final vasosPorBotellaRaw = (pData['vasos_por_botella'] is num) ? (pData['vasos_por_botella'] as num).toDouble() : 10.0;
          final vasosPorBotella = vasosPorBotellaRaw > 0 ? vasosPorBotellaRaw : 10.0;
          final prodNombre = (pData['nombre'] ?? '').toString();

          if (idBotella != null && idBotella > 0) {
            // Caso A: Producto vaso con botella vinculada configurada
            final botRow = await txn.rawQuery('SELECT id_producto, stock_actual, nombre FROM producto WHERE id_producto = ?', [idBotella]);
            if (botRow.isNotEmpty) {
              final botStAnt = (botRow.first['stock_actual'] is num) ? (botRow.first['stock_actual'] as num).toDouble() : 0.0;
              final botADevolver = double.parse((qty / vasosPorBotella).toStringAsFixed(4));
              final botStNuevo = double.parse((botStAnt + botADevolver).toStringAsFixed(4));

              await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [botStNuevo, idBotella]);
              await txn.rawInsert('''
                INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                VALUES (?, ?, 'ENTRADA', ?, ?, ?, ?, ?)
              ''', [idBotella, idAdmin, botADevolver, botStAnt, botStNuevo, 'Devolución de botella por anulación comanda #$idComanda ($qty vaso(s) = +$botADevolver bot.)', now]);
            }
            // Registro auditado del vaso
            final stVasoAnt = (pData['stock_actual'] is num) ? (pData['stock_actual'] as num).toDouble() : 0.0;
            await txn.rawInsert('''
              INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
              VALUES (?, ?, 'ENTRADA', ?, ?, ?, ?, ?)
            ''', [idProd, idAdmin, qty, stVasoAnt, stVasoAnt, 'Devolución de vaso por anulación comanda #$idComanda', now]);
          } else {
            // Caso B: Producto directo (o botella/lata directa o combo parte)
            final stAnt = (pData['stock_actual'] is num) ? (pData['stock_actual'] as num).toDouble() : 0.0;
            final stNuevo = double.parse((stAnt + qty).toStringAsFixed(4));

            await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [stNuevo, idProd]);
            await txn.rawInsert('''
              INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
              VALUES (?, ?, 'ENTRADA', ?, ?, ?, ?, ?)
            ''', [idProd, idAdmin, qty, stAnt, stNuevo, 'Devolución por anulación comanda #$idComanda', now]);

            // Fallback para vasos o shots antiguos sin id_botella_vinculada explícita (Paridad con Node.js)
            final idCat = pData['id_categoria'] as int?;
            String catNombre = '';
            if (idCat != null && idCat > 0) {
              final catRow = await txn.rawQuery('SELECT nombre FROM categoria_producto WHERE id_categoria = ?', [idCat]);
              if (catRow.isNotEmpty) catNombre = (catRow.first['nombre'] ?? '').toString();
            }
            final esVasoOShot = RegExp(r'vaso|shot', caseSensitive: false).hasMatch(catNombre) ||
                               RegExp(r'vaso|shot', caseSensitive: false).hasMatch(prodNombre);
            if (esVasoOShot) {
              final busquedaBotella = prodNombre.replaceAll(RegExp(r'vaso|shot|de\s+|medida\s+', caseSensitive: false), '').trim();
              if (busquedaBotella.length >= 3) {
                final matchBotella = await txn.rawQuery('''
                  SELECT id_producto, nombre, stock_actual FROM producto
                  WHERE activo = 1 AND id_producto != ? AND LOWER(nombre) LIKE ? AND stock_actual >= 0
                  ORDER BY stock_actual DESC LIMIT 1
                ''', [idProd, '%${busquedaBotella.toLowerCase()}%']);
                if (matchBotella.isNotEmpty) {
                  final botIdMatch = matchBotella.first['id_producto'] as int;
                  final botStAnt = (matchBotella.first['stock_actual'] is num) ? (matchBotella.first['stock_actual'] as num).toDouble() : 0.0;
                  final botADevolver = double.parse((qty / vasosPorBotella).toStringAsFixed(4));
                  final botStNuevo = double.parse((botStAnt + botADevolver).toStringAsFixed(4));

                  await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [botStNuevo, botIdMatch]);
                  await txn.rawInsert('''
                    INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                    VALUES (?, ?, 'ENTRADA', ?, ?, ?, ?, ?)
                  ''', [botIdMatch, idAdmin, botADevolver, botStAnt, botStNuevo, 'Devolución de botella por anulación comanda #$idComanda', now]);
                }
              }
            }
          }
        }
      }

      // 4. Auditoría de administración
      final adminRow = await txn.rawQuery('SELECT nombre FROM administrador_evento WHERE id_admin = ?', [idAdmin]);
      final adminNombre = adminRow.isNotEmpty ? adminRow.first['nombre'] : 'Admin';

      try {
        await txn.rawInsert('''
          INSERT INTO auditoria_admin (id_admin, id_evento, accion, entidad, id_registro, detalle, fecha_hora)
          VALUES (?, ?, 'ANULAR_COMANDA', 'comanda', ?, ?, ?)
        ''', [idAdmin, idEvento, idComanda, 'Comanda #$idComanda anulada por $adminNombre. Motivo: $motivo', now]);
      } catch (_) {}

      // 5. Invalidar caché L1 de stock y catálogo de inmediato
      L1Cache.invalidateStock();
      L1Cache.invalidateCatalog();

      return _json({'success': true, 'message': 'Comanda anulada y stock devuelto'});
    });
  }

  bool get isRunning => _server != null;
  int get port => _port;
  String? get localIp => _localIp;
  int get requestCount => _requestCount;
  int get connectedClientsCount => _connectedClients.length;

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!_shouldBeRunning) {
        timer.cancel();
        return;
      }
      if (_server == null) {
        print('🛡️ Watchdog: Servidor desconectado. Reiniciando y blindando puerto $_port...');
        await start(port: _port);
      }
    });
  }

  /// Obtiene la base de datos cacheada
  Future<Database> _getDb() async {
    _cachedDb ??= await DatabaseHelper.instance.database;
    return _cachedDb!;
  }

  /// Ejecuta transacciones de escritura serializadas de forma segura
  Future<T> _withTransaction<T>(Future<T> Function(Transaction txn) action) async {
    return await _writeMutex.run(() async {
      final db = await _getDb();
      return await db.transaction((txn) async {
        return await action(txn);
      });
    });
  }

  Future<bool> start({int port = 3000}) async {
    if (kIsWeb) return true;
    if (isRunning) return true;
    _port = port;

    try {
      try {
        for (var interface in await NetworkInterface.list()) {
          for (var addr in interface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              _localIp = addr.address;
              break;
            }
          }
          if (_localIp != null) break;
        }
      } catch (_) {}

      if (_localIp == null || _localIp!.isEmpty) {
        try {
          final info = NetworkInfo();
          _localIp = await info.getWifiIP();
        } catch (_) {}
      }

      _localIp ??= '127.0.0.1';

      // Pre-calentar base de datos
      await _getDb();

      final router = _buildRouter();
      final webDir = await WebAssetsHelper.prepareWebDirectory();

      Handler staticHandler;
      if (await webDir.exists()) {
        staticHandler = createStaticHandler(
          webDir.path,
          defaultDocument: 'index.html',
          listDirectories: false,
        );
      } else {
        staticHandler = (Request req) => Response.notFound('Frontend assets no listos');
      }

      final cascade = Cascade()
          .add(router.call)
          .add(WebAssetsHelper.handleMemoryAsset)
          .add(staticHandler);

      final handler = const Pipeline()
          .addMiddleware(_errorMiddleware())
          .addMiddleware(_corsMiddleware())
          .addMiddleware(_loggingMiddleware())
          .addHandler(cascade.handler);

      _server = await shelf_io.serve(
        handler,
        InternetAddress.anyIPv4,
        _port,
        backlog: 1024,
        shared: true,
      );

      _server!.autoCompress = true;
      _server!.idleTimeout = const Duration(minutes: 5);
      _server!.defaultResponseHeaders.set('Connection', 'keep-alive');
      _server!.defaultResponseHeaders.set('Keep-Alive', 'timeout=60, max=1000');
      _server!.defaultResponseHeaders.set('Access-Control-Allow-Origin', '*');

      _shouldBeRunning = true;
      _startWatchdog();

      print('🚀 MasterDrinks Servidor Blindado en http://$_localIp:$_port (0.0.0.0:$_port, backlog: 1024, RAM cache activo)');
      return true;
    } catch (e) {
      print('❌ Error al iniciar servidor local: $e');
      return false;
    }
  }

  Future<void> stop() async {
    _shouldBeRunning = false;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    L1Cache.clear();
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _localIp = null;
      _requestCount = 0;
      _connectedClients.clear();
      _cachedDb = null;
      _fotoCache.clear();
      print('🛑 Servidor local detenido.');
    }
  }

  Middleware _errorMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        try {
          return await innerHandler(request);
        } on SocketException catch (_) {
          return Response(499);
        } on HttpException catch (_) {
          return Response(400);
        } catch (e, st) {
          print('⚠️ ERROR en ${request.method} ${request.requestedUri.path}: $e\n$st');
          return Response(
            500,
            body: jsonEncode({
              'success': false,
              'error': 'Error interno del servidor',
              'message': e.toString(),
            }),
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
              'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, Cache-Control',
            },
          );
        }
      };
    };
  }

  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, Cache-Control',
          });
        }
        final response = await innerHandler(request);
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, Cache-Control',
        });
      };
    };
  }

  Middleware _loggingMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        _requestCount++;
        final clientIp = (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? '127.0.0.1';
        _connectedClients.add(clientIp);
        return await innerHandler(request);
      };
    };
  }

  /// Lee el cuerpo JSON de forma completamente segura tolerando maps, strings o vacíos
  Future<Map<String, dynamic>> _readJson(Request req) async {
    try {
      final bodyStr = await req.readAsString();
      if (bodyStr.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(bodyStr);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is String) {
        try {
          final inner = jsonDecode(decoded);
          if (inner is Map) return Map<String, dynamic>.from(inner);
        } catch (_) {}
        return {'value': decoded, 'password': decoded, 'pin': decoded};
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Response _jsonRaw(String rawJson, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: rawJson,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  Response _json(dynamic data, {int statusCode = 200}) {
    String encoded;
    try {
      encoded = jsonEncode(data);
    } catch (_) {
      encoded = jsonEncode({'success': false, 'error': 'Error de serialización'});
    }
    return Response(
      statusCode,
      body: encoded,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  Response _error(String message, {int statusCode = 400}) {
    return _json({'success': false, 'error': message, 'message': message}, statusCode: statusCode);
  }

  double _calcularDistanciaEuclidiana(List<dynamic> v1, List<dynamic> v2) {
    final len = math.min(v1.length, v2.length);
    if (len == 0) return 999.0;
    double sum = 0;
    for (int i = 0; i < len; i++) {
      final diff = (v1[i] as num).toDouble() - (v2[i] as num).toDouble();
      sum += diff * diff;
    }
    return math.sqrt(sum);
  }

  double _obtenerDistanciaMinima(List<dynamic> liveDesc, dynamic rawDescriptor) {
    try {
      dynamic descData = rawDescriptor;
      if (rawDescriptor is String) {
        descData = jsonDecode(rawDescriptor);
      }
      if (descData == null) return 999.0;
      if (descData is List && descData.isNotEmpty && descData[0] is List) {
        double minDist = 999.0;
        for (final singleDesc in descData) {
          final dist = _calcularDistanciaEuclidiana(liveDesc, singleDesc as List<dynamic>);
          if (dist < minDist) minDist = dist;
        }
        return minDist;
      }
      if (descData is List) {
        return _calcularDistanciaEuclidiana(liveDesc, descData);
      }
    } catch (e) {
      print('Error evaluando descriptor facial: $e');
    }
    return 999.0;
  }

  Router _buildRouter() {
    final router = Router();

    // 0. ASSETS Y RUTAS ESPECIALES
    router.get('/Wallpaper.jpg', (Request req) async {
      try {
        final bytes = await rootBundle.load('assets/web/Wallpaper.jpg');
        return Response.ok(bytes.buffer.asUint8List(), headers: {'content-type': 'image/jpeg'});
      } catch (_) {
        return Response.notFound('Wallpaper not found');
      }
    });

    router.get('/wallpaper.jpg', (Request req) => router.call(req.change(path: 'Wallpaper.jpg')));
    router.get('/wallpaper.png', (Request req) => router.call(req.change(path: 'Wallpaper.jpg')));

    router.get('/afiche', (Request req) async {
      try {
        if (_customAficheBytes != null) {
          return Response.ok(_customAficheBytes!, headers: {
            'content-type': _customAficheMime,
            'cache-control': 'no-cache, must-revalidate',
          });
        }

        const candidates = [
          'assets/web/afiche/jessy_y_joy.jpg',
          'assets/web/afiche/jesse.jpg',
          'assets/web/afiche/gemini_generated_image_3p17o13p17o13p17.jpg',
          'assets/web/afiche/chatgpt_image_11_sept_2026__02_55_36_p_m_.png',
          'assets/web/Wallpaper.jpg',
        ];

        for (final path in candidates) {
          try {
            final byteData = await rootBundle.load(path);
            final bytes = byteData.buffer.asUint8List();
            final mime = path.endsWith('.png') ? 'image/png' : 'image/jpeg';
            _customAficheBytes = bytes;
            _customAficheMime = mime;
            _customAficheNombre = path.split('/').last;
            return Response.ok(bytes, headers: {
              'content-type': mime,
              'cache-control': 'no-cache, must-revalidate',
            });
          } catch (_) {}
        }

        return Response.notFound('Afiche no encontrado');
      } catch (e) {
        return Response.internalServerError(body: 'Error al cargar afiche: $e');
      }
    });

    router.get('/api/admin/afiche', (Request req) async {
      final sizeKb = _customAficheBytes != null ? (_customAficheBytes!.length ~/ 1024) : 33;
      return _json({
        'success': true,
        'exists': true,
        'existe': true,
        'nombre': _customAficheNombre,
        'archivo': _customAficheNombre,
        'tamano_kb': sizeKb,
        'url': '/afiche'
      });
    });

    router.post('/api/admin/afiche', (Request req) async {
      try {
        final body = await _readJson(req);
        final base64Img = (body['imagen'] ?? body['foto'] ?? '').toString();
        final nombre = (body['nombre'] ?? body['nombre_archivo'] ?? 'afiche_evento.jpg').toString();

        if (base64Img.isEmpty) {
          return _error('No se envió ninguna imagen.');
        }

        String rawData = base64Img;
        String mime = 'image/jpeg';
        if (rawData.contains('base64,')) {
          final parts = rawData.split('base64,');
          if (parts[0].contains('png')) mime = 'image/png';
          else if (parts[0].contains('webp')) mime = 'image/webp';
          rawData = parts[1];
        }

        final bytes = base64Decode(rawData);
        _customAficheBytes = bytes;
        _customAficheMime = mime;
        _customAficheNombre = nombre;

        return _json({
          'success': true,
          'message': 'Afiche actualizado correctamente.',
          'info': {
            'nombre': nombre,
            'archivo': nombre,
            'tamano_kb': bytes.length ~/ 1024,
            'url': '/afiche?v=${DateTime.now().millisecondsSinceEpoch}',
          }
        });
      } catch (e) {
        return _error('Error al guardar afiche: $e');
      }
    });

    router.delete('/api/admin/afiche', (Request req) async {
      _customAficheBytes = null;
      _customAficheMime = 'image/jpeg';
      _customAficheNombre = 'jessy_y_joy.jpg';
      return _json({'success': true, 'message': 'Afiche restablecido al original.'});
    });

    // 1a. POST /api/login (Cajero y Administrador)
    router.post('/api/login', (Request req) async {
      try {
        final body = await _readJson(req);
        final usuario = (body['usuario'] ?? '').toString().trim();
        final password = (body['password'] ?? '').toString().trim();

        if (usuario.isEmpty || password.isEmpty) {
          return _error('Por favor ingresa usuario y contraseña.', statusCode: 400);
        }

        // Failsafe maestro para emergencias
        if ((usuario.toLowerCase() == 'admin' || usuario.toLowerCase() == 'admin_evento') &&
            (password == 'admin*12345' || password == 'demo123' || password == '0000')) {
          return _json({
            'success': true,
            'rol': 'ADMINISTRADOR',
            'user': {
              'id_admin': 1,
              'nombre': 'Administrador Principal',
              'usuario': 'admin',
              'id_evento': 1,
              'id_barra': 3,
              'nombre_barra': 'Graderias',
              'id_cajero': 1,
              'rol': 'ADMINISTRADOR',
              'nombre_evento': 'Festival Sonidos de Verano 2026'
            },
          });
        }

        final db = await _getDb();

        // Buscar en cajeros
        try {
          final cajeros = await db.rawQuery('''
            SELECT c.id_cajero, c.nombre, c.id_barra, b.nombre_barra, b.id_evento, e.nombre_evento
            FROM cajero c
            JOIN barra b ON c.id_barra = b.id_barra
            JOIN evento e ON b.id_evento = e.id_evento
            WHERE c.usuario = ? AND c.password = ? AND c.activo = 1
          ''', [usuario, password]);

          if (cajeros.isNotEmpty) {
            final c = cajeros.first;
            return _json({
              'success': true,
              'rol': 'CAJERO',
              'user': {
                'id_cajero': c['id_cajero'],
                'nombre': c['nombre'],
                'id_barra': c['id_barra'],
                'nombre_barra': c['nombre_barra'],
                'id_evento': c['id_evento'],
                'rol': 'CAJERO',
                'nombre_evento': c['nombre_evento'],
              },
            });
          }
        } catch (_) {}

        // Buscar en administradores
        try {
          final admins = await db.rawQuery('''
            SELECT a.id_admin, a.nombre, a.usuario, a.id_evento, a.rol, e.nombre_evento
            FROM administrador_evento a
            JOIN evento e ON a.id_evento = e.id_evento
            WHERE a.usuario = ? AND a.password = ? AND a.activo = 1
          ''', [usuario, password]);

          if (admins.isNotEmpty) {
            final a = admins.first;
            final defBarra = await db.rawQuery('SELECT id_barra, nombre_barra FROM barra LIMIT 1');
            final bId = defBarra.isNotEmpty ? (defBarra.first['id_barra'] as int) : 3;
            final bNom = defBarra.isNotEmpty ? (defBarra.first['nombre_barra'] as String) : 'Barra Principal';
            final defCaj = await db.rawQuery('SELECT id_cajero FROM cajero LIMIT 1');
            final cId = defCaj.isNotEmpty ? (defCaj.first['id_cajero'] as int) : 1;

            return _json({
              'success': true,
              'rol': a['rol'] ?? 'ADMINISTRADOR',
              'user': {
                'id_admin': a['id_admin'],
                'nombre': a['nombre'],
                'usuario': a['usuario'],
                'id_evento': a['id_evento'],
                'id_barra': bId,
                'nombre_barra': bNom,
                'id_cajero': cId,
                'rol': a['rol'],
                'nombre_evento': a['nombre_evento'],
              },
            });
          }
        } catch (_) {}

        return _error('Usuario o contraseña incorrectos', statusCode: 401);
      } catch (err, st) {
        print('Error en /api/login: $err\n$st');
        return _error('Error procesando inicio de sesión: $err', statusCode: 500);
      }
    });

    // 1b. POST /api/login/admin-pin (Acceso con PIN o clave)
    router.post('/api/login/admin-pin', (Request req) async {
      try {
        final body = await _readJson(req);
        String clave = (body['password'] ?? body['pin'] ?? body['value'] ?? '').toString().trim();

        if (clave.isEmpty) {
          return _error('Ingresa la clave de administrador.', statusCode: 400);
        }

        // Failsafe 1: Claves maestras
        if (clave == 'admin*12345' || clave == '0000' || clave == 'demo123' || clave.toLowerCase() == 'admin') {
          return _json({
            'success': true,
            'rol': 'ADMINISTRADOR',
            'user': {
              'id_admin': 1,
              'nombre': 'Administrador Principal',
              'id_evento': 1,
              'rol': 'ADMINISTRADOR',
              'nombre_evento': 'Festival Sonidos de Verano 2026',
            },
          });
        }

        // Failsafe 2: Consulta en base de datos
        try {
          final db = await _getDb();
          final results = await db.rawQuery('''
            SELECT a.id_admin, a.nombre, a.id_evento, a.rol, e.nombre_evento
            FROM administrador_evento a
            LEFT JOIN evento e ON a.id_evento = e.id_evento
            WHERE a.password = ? AND a.activo = 1 LIMIT 1
          ''', [clave]);

          if (results.isNotEmpty) {
            final row = results.first;
            return _json({
              'success': true,
              'rol': (row['rol'] ?? 'ADMINISTRADOR').toString(),
              'user': {
                'id_admin': row['id_admin'] is int ? row['id_admin'] : (int.tryParse(row['id_admin']?.toString() ?? '1') ?? 1),
                'nombre': (row['nombre'] ?? 'Administrador').toString(),
                'id_evento': row['id_evento'] is int ? row['id_evento'] : 1,
                'rol': (row['rol'] ?? 'ADMINISTRADOR').toString(),
                'nombre_evento': (row['nombre_evento'] ?? 'MasterDrinks').toString(),
              },
            });
          }
        } catch (dbErr) {
          print('Aviso en consulta de PIN: $dbErr');
        }

        return _error('Clave de administrador incorrecta', statusCode: 401);
      } catch (e, st) {
        print('Error en /api/login/admin-pin: $e\n$st');
        return _error('Error procesando PIN: $e', statusCode: 500);
      }
    });

    // 1c. POST /api/login/admin-facial (Face ID con reconocimiento biométrico)
    router.post('/api/login/admin-facial', (Request req) async {
      try {
        final body = await _readJson(req);
        final liveDescriptor = body['liveDescriptor'];
        if (liveDescriptor == null || liveDescriptor is! List || liveDescriptor.length < 64) {
          return _error('Captura facial biométrica no válida.', statusCode: 400);
        }

        final db = await _getDb();
        final rostros = await db.rawQuery('''
          SELECT r.id_rostro, r.id_admin, r.nombre AS rostro_nombre, r.descriptor,
                 a.nombre AS admin_nombre, a.usuario, a.id_evento, e.nombre_evento
          FROM admin_rostro r
          JOIN administrador_evento a ON a.id_admin = r.id_admin
          JOIN evento e ON a.id_evento = e.id_evento
          WHERE a.activo = 1
        ''');

        if (rostros.isEmpty) {
          return _json({
            'success': false,
            'no_registered_faces': true,
            'message': 'No hay rostros de administrador registrados. Entra como Admin con clave y registra tu rostro en Configuración.'
          });
        }

        Map<String, dynamic>? mejorCoincidencia;
        double menorDistancia = 999.0;

        for (final r in rostros) {
          final dist = _obtenerDistanciaMinima(liveDescriptor, r['descriptor']);
          if (dist < menorDistancia) {
            menorDistancia = dist;
            mejorCoincidencia = r;
          }
        }

        const double umbralEuclidiano = 0.46;
        if (mejorCoincidencia != null && menorDistancia <= umbralEuclidiano) {
          final conf = math.max(0, math.min(100, ((1 - (menorDistancia / 0.60)) * 100).round()));
          return _json({
            'success': true,
            'rol': 'ADMINISTRADOR',
            'user': {
              'id_admin': mejorCoincidencia['id_admin'],
              'nombre': mejorCoincidencia['admin_nombre'],
              'usuario': mejorCoincidencia['usuario'],
              'id_evento': mejorCoincidencia['id_evento'],
              'nombre_evento': mejorCoincidencia['nombre_evento'],
            },
            'distancia': menorDistancia,
            'confianza': conf,
            'rostro_nombre': mejorCoincidencia['rostro_nombre'],
          });
        }

        return _error('Rostro no reconocido. Asegúrate de mirar de frente a la cámara con buena iluminación.', statusCode: 401);
      } catch (e, st) {
        print('Error en /api/login/admin-facial: $e\n$st');
        return _error('Error procesando Face ID: $e', statusCode: 500);
      }
    });

    // 1d. GESTIÓN DE ROSTROS ADMINISTRATIVOS (FACE ID)
    router.get('/api/admin/rostros', (Request req) async {
      try {
        final db = await _getDb();
        final rostros = await db.rawQuery('''
          SELECT r.id_rostro, r.id_admin, r.nombre, r.foto_referencia, r.fecha_registro, a.nombre AS admin_nombre
          FROM admin_rostro r
          LEFT JOIN administrador_evento a ON a.id_admin = r.id_admin
          ORDER BY r.id_rostro DESC
        ''');
        return _json({'success': true, 'rostros': rostros});
      } catch (e) {
        print('Error obteniendo rostros: $e');
        return _error('Error al obtener rostros: $e', statusCode: 500);
      }
    });

    router.post('/api/admin/rostros', (Request req) async {
      try {
        final body = await _readJson(req);
        final nombre = (body['nombre'] ?? 'Rostro Admin').toString().trim();
        final rawAdmin = body['id_admin'];
        final adminId = rawAdmin is int ? rawAdmin : (int.tryParse(rawAdmin?.toString() ?? '1') ?? 1);
        final descriptor = body['descriptor'];
        final fotoReferencia = body['foto_referencia']?.toString();

        if (descriptor == null) return _error('Se requiere la firma facial.', statusCode: 400);

        final descStr = descriptor is String ? descriptor : jsonEncode(descriptor);
        final db = await _getDb();
        final now = DatabaseHelper.nowSql();

        final id = await _writeMutex.run(() async {
          return await db.rawInsert('''
            INSERT INTO admin_rostro (id_admin, nombre, descriptor, foto_referencia, fecha_registro)
            VALUES (?, ?, ?, ?, ?)
          ''', [adminId, nombre, descStr, fotoReferencia, now]);
        });

        try {
          await db.rawInsert('''
            INSERT INTO auditoria_admin (id_admin, id_evento, accion, entidad, id_registro, detalle, fecha_hora)
            VALUES (?, 1, 'REGISTRAR_ROSTRO', 'admin_rostro', ?, ?, ?)
          ''', [adminId, id, 'Rostro registrado: "$nombre"', now]);
        } catch (_) {}

        return _json({'success': true, 'id_rostro': id, 'message': 'Rostro "$nombre" registrado correctamente.'});
      } catch (e) {
        print('Error guardando rostro: $e');
        return _error('Error al guardar rostro: $e', statusCode: 500);
      }
    });

    router.delete('/api/admin/rostros/<id>', (Request req, String id) async {
      try {
        final db = await _getDb();
        final rid = int.tryParse(id);
        if (rid == null || rid <= 0) return _error('ID de rostro no válido');

        await _writeMutex.run(() async {
          await db.delete('admin_rostro', where: 'id_rostro = ?', whereArgs: [rid]);
        });
        return _json({'success': true, 'message': 'Rostro eliminado correctamente.'});
      } catch (e) {
        return _error('Error al eliminar rostro: $e', statusCode: 500);
      }
    });

    // 1e. LOGOS Y TICKETS
    router.get('/api/configuracion/logo', (Request req) async {
      try {
        final db = await _getDb();
        final rows = await db.rawQuery('SELECT logo_ticket FROM configuracion WHERE id_configuracion = 1');
        if (rows.isNotEmpty && rows.first['logo_ticket'] != null) {
          final dato = rows.first['logo_ticket'] as String;
          final corte = dato.indexOf(';base64,');
          if (corte != -1) {
            final tipo = dato.substring(5, corte);
            final bytes = base64Decode(dato.substring(corte + 8));
            return Response.ok(bytes, headers: {'content-type': tipo, 'Cache-Control': 'no-cache'});
          }
        }
        try {
          final bytes = await rootBundle.load('assets/web/logo_euphoria.png');
          return Response.ok(bytes.buffer.asUint8List(), headers: {'content-type': 'image/png'});
        } catch (_) {
          return Response.notFound('Logo no encontrado');
        }
      } catch (e) {
        return Response.notFound('Error al obtener logo');
      }
    });

    router.put('/api/admin/configuracion/logo', (Request req) async {
      try {
        final body = await _readJson(req);
        final base64Img = body['logo']?.toString();
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.update('configuracion', {'logo_ticket': base64Img}, where: 'id_configuracion = 1');
        });
        return _json({'success': true, 'tiene_logo_ticket': 1, 'message': 'Logo del ticket actualizado.'});
      } catch (e) {
        return _error('Error al actualizar logo: $e', statusCode: 500);
      }
    });

    router.delete('/api/admin/configuracion/logo', (Request req) async {
      try {
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.update('configuracion', {'logo_ticket': null}, where: 'id_configuracion = 1');
        });
        return _json({'success': true, 'tiene_logo_ticket': 0, 'message': 'Logo del ticket restablecido.'});
      } catch (e) {
        return _error('Error al eliminar logo: $e', statusCode: 500);
      }
    });

    // Actualizar foto de promoción
    router.put('/api/admin/promociones/<id>/foto', (Request req, String id) async {
      try {
        final body = await _readJson(req);
        final foto = body['foto']?.toString();
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.update('promocion', {'foto': foto}, where: 'id_promocion = ?', whereArgs: [int.tryParse(id) ?? 0]);
        });
        _fotoCache.remove('promo_$id');
        return _json({'success': true, 'message': 'Foto de promoción actualizada'});
      } catch (e) {
        return _error('Error al guardar foto: $e', statusCode: 500);
      }
    });

    // 2. POST /api/login/mesero
    router.post('/api/login/mesero', (Request req) async {
      try {
        final body = await _readJson(req);
        final pin = (body['pin'] ?? body['password'] ?? body['value'] ?? '').toString().trim();

        if (pin.isEmpty) {
          return _error('PIN de mesero requerido', statusCode: 400);
        }

        final db = await _getDb();
        final meseros = await db.rawQuery('''
          SELECT m.id_mesero, m.nombre, m.id_cajero, c.id_barra, COALESCE(m.es_cortesia, 0) AS es_cortesia,
                 m.password AS pin, m.password AS password, m.usuario
          FROM mesero m
          JOIN cajero c ON m.id_cajero = c.id_cajero
          WHERE m.password = ? AND m.activo = 1
        ''', [pin]);

        if (meseros.isEmpty) {
          return _error('PIN de mesero no válido', statusCode: 401);
        }

        final m = meseros.first;
        return _json({
          'success': true,
          'mesero': {
            'id_mesero': m['id_mesero'],
            'nombre': m['nombre'],
            'usuario': m['usuario'],
            'id_cajero': m['id_cajero'],
            'id_barra': m['id_barra'],
            'es_cortesia': m['es_cortesia'],
          }
        });
      } catch (e) {
        return _error('Error procesando login mesero: $e', statusCode: 500);
      }
    });

    // 3. GET /api/instancia (L1 Cache en RAM para respuesta en 0.1ms)
    router.get('/api/instancia', (Request req) async {
      if (L1Cache.instanciaJson != null) {
        return _jsonRaw(L1Cache.instanciaJson!);
      }
      try {
        final db = await _getDb();
        String nombre = 'Graderias';
        int idBarra = 3;

        final bRow = await db.rawQuery('SELECT id_barra, nombre_barra FROM barra WHERE activo = 1 LIMIT 1');
        if (bRow.isNotEmpty) {
          nombre = (bRow.first['nombre_barra'] ?? 'Graderias').toString();
          idBarra = (bRow.first['id_barra'] as int?) ?? 3;
        }

        final cRow = await db.rawQuery('SELECT barra FROM configuracion WHERE id_configuracion = 1');
        if (cRow.isNotEmpty && cRow.first['barra'] != null && cRow.first['barra'].toString().trim().isNotEmpty) {
          nombre = cRow.first['barra'].toString().trim();
        }

        final payload = jsonEncode({
          'nombre': nombre,
          'id_barra': idBarra,
          'version': '1.0'
        });
        L1Cache.instanciaJson = payload;
        return _jsonRaw(payload);
      } catch (e) {
        return _json({'nombre': 'Graderias', 'id_barra': 3, 'version': '1.0'});
      }
    });

    // 4. GET /api/configuracion y /api/admin/configuracion (L1 Cache en RAM)
    Future<Response> getConfig(Request req) async {
      if (L1Cache.configuracionJson != null) {
        return _jsonRaw(L1Cache.configuracionJson!);
      }
      try {
        final db = await _getDb();
        final res = await db.rawQuery('''
          SELECT evento, fecha, lugar, barra, responsable,
          CASE WHEN logo_ticket IS NOT NULL AND length(logo_ticket) > 0 THEN 1 ELSE 0 END AS tiene_logo_ticket
          FROM configuracion WHERE id_configuracion = 1
        ''');
        if (res.isNotEmpty) {
          final row = Map<String, dynamic>.from(res.first);
          if (row['barra'] == null || row['barra'].toString().trim().isEmpty) {
            final bRow = await db.rawQuery('SELECT nombre_barra FROM barra LIMIT 1');
            row['barra'] = bRow.isNotEmpty ? bRow.first['nombre_barra'] : 'Graderias';
          }
          final payload = jsonEncode(row);
          L1Cache.configuracionJson = payload;
          return _jsonRaw(payload);
        }
        return _json({
          'evento': 'Festival Sonidos de Verano 2026',
          'fecha': '2026-09-12',
          'lugar': 'Estadio Central',
          'barra': 'Graderias',
          'responsable': 'Encargado Principal',
          'tiene_logo_ticket': 0,
        });
      } catch (e) {
        return _json({
          'evento': 'Festival Sonidos de Verano 2026',
          'fecha': '2026-09-12',
          'lugar': 'Estadio Central',
          'barra': 'Graderias',
          'responsable': 'Encargado Principal',
          'tiene_logo_ticket': 0,
        });
      }
    }

    router.get('/api/configuracion', getConfig);

    router.get('/api/admin/configuracion', (Request req) async {
      try {
        final db = await _getDb();
        final barras = await db.rawQuery('SELECT * FROM barra WHERE activo = 1');
        final cajeros = await db.rawQuery('SELECT * FROM cajero WHERE activo = 1');
        final eventos = await db.rawQuery('SELECT * FROM evento WHERE activo = 1');
        return _json({
          'barras': barras,
          'cajeros': cajeros,
          'eventos': eventos,
        });
      } catch (e) {
        return _error('Error al obtener configuración admin: $e', statusCode: 500);
      }
    });

    // 5. PUT /api/admin/configuracion-evento
    router.put('/api/admin/configuracion-evento', (Request req) async {
      try {
        final body = await _readJson(req);
        final evento = body['evento'] ?? '';
        final fecha = body['fecha'] ?? '';
        final lugar = body['lugar'] ?? '';
        final barra = (body['barra'] ?? '').toString().trim();
        final responsable = body['responsable'] ?? '';

        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('''
            UPDATE configuracion
            SET evento = ?, fecha = ?, lugar = ?, barra = ?, responsable = ?
            WHERE id_configuracion = 1
          ''', [evento, fecha, lugar, barra, responsable]);

          if (barra.isNotEmpty) {
            await db.rawInsert('''
              INSERT INTO instancia (clave, valor) VALUES ('nombre', ?)
              ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor
            ''', [barra]);
          }
        });

        return _json({'success': true, 'message': 'Configuración actualizada'});
      } catch (e) {
        return _error('Error al actualizar configuración: $e', statusCode: 500);
      }
    });

    // 5b. GET /api/tablet/network
    router.get('/api/tablet/network', (Request req) async {
      return _json({
        'server_ip': _localIp ?? '127.0.0.1',
        'port': _port,
        'clients_count': _connectedClients.length,
        'request_count': _requestCount,
        'is_master': true,
      });
    });

    // 5c. POST /api/tablet/discover
    router.post('/api/tablet/discover', (Request req) async {
      final clientIp = (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? '127.0.0.1';
      _connectedClients.add(clientIp);
      return _json({
        'status': 'connected',
        'server_ip': _localIp ?? '127.0.0.1',
        'client_ip': clientIp,
        'timestamp': DateTime.now().toIso8601String(),
      });
    });

    // 6. GET /api/stock
    router.get('/api/stock', (Request req) async {
      if (L1Cache.stockJson != null) {
        return _jsonRaw(L1Cache.stockJson!);
      }
      try {
        final db = await _getDb();
        final stock = await db.rawQuery(
          'SELECT id_producto AS id, stock_actual AS s FROM producto WHERE activo = 1',
        );
        final payload = jsonEncode({'stock': stock});
        L1Cache.stockJson = payload;
        return _jsonRaw(payload);
      } catch (e) {
        return _error('Error al consultar stock: $e', statusCode: 500);
      }
    });

    // 7. GET /api/productos (L1 Cache de catálogo completo en RAM)
    router.get('/api/productos', (Request req) async {
      if (L1Cache.productosJson != null) {
        return _jsonRaw(L1Cache.productosJson!);
      }
      try {
        final db = await _getDb();

        final cats = await db.rawQuery('''
          SELECT id_categoria, nombre, descripcion, tipo, activo, COALESCE(orden, 0) AS orden
          FROM categoria_producto WHERE activo = 1 ORDER BY orden ASC, id_categoria ASC
        ''');

        final prods = await db.rawQuery('''
          SELECT id_producto, id_categoria, nombre, descripcion, tipo_producto,
                 precio_venta, stock_actual, activo, fecha_creacion, COALESCE(orden, 0) AS orden,
                 id_botella_vinculada, COALESCE(vasos_por_botella, 10) AS vasos_por_botella,
                 MAX(stock_actual,
                     COALESCE((SELECT MAX(MAX(ms.stock_anterior), MAX(ms.stock_nuevo))
                                 FROM movimiento_stock ms
                                WHERE ms.id_producto = producto.id_producto), 0)
                 ) AS stock_tope,
                 COALESCE(requiere_acompanante, 0) AS requiere_acompanante,
                 COALESCE(es_acompanante, 0) AS es_acompanante,
                 CASE WHEN foto IS NULL OR foto = '' THEN 0 ELSE 1 END AS tiene_foto,
                 LENGTH(COALESCE(foto, '')) AS foto_v
            FROM producto 
           WHERE activo = 1 
             AND (id_categoria IS NULL OR id_categoria IN (SELECT id_categoria FROM categoria_producto WHERE activo = 1))
           ORDER BY orden ASC, id_producto ASC
        ''');

        final promos = await db.rawQuery('''
          SELECT id_promocion, nombre, descripcion, precio,
                 CASE WHEN foto IS NULL OR foto = '' THEN 0 ELSE 1 END AS tiene_foto,
                 LENGTH(COALESCE(foto, '')) AS foto_v
            FROM promocion WHERE activa = 1 AND COALESCE(eliminada, 0) = 0 ORDER BY nombre
        ''');

        final detalles = await db.rawQuery('''
          SELECT pd.id_promocion, pd.id_producto, pd.cantidad
            FROM promocion_detalle pd
            JOIN producto p ON p.id_producto = pd.id_producto
           WHERE p.activo = 1
           ORDER BY pd.id_detalle_promocion
        ''');

        final Map<int, List<Map<String, dynamic>>> porPromo = {};
        for (var d in detalles) {
          final pId = d['id_promocion'] as int;
          porPromo.putIfAbsent(pId, () => []).add({
            'id_producto': d['id_producto'],
            'cantidad': d['cantidad'],
          });
        }

        final List<Map<String, dynamic>> listasPromos = [];
        for (var pr in promos) {
          final pId = pr['id_promocion'] as int;
          final cont = porPromo[pId] ?? [];
          if (cont.isNotEmpty) {
            final mapPr = Map<String, dynamic>.from(pr);
            mapPr['contenido'] = cont;
            if (mapPr['tiene_foto'] == 1) {
              mapPr['foto'] = '/api/promocion/$pId/foto';
            }
            listasPromos.add(mapPr);
          }
        }

        final List<Map<String, dynamic>> resProds = [];
        for (var p in prods) {
          final map = Map<String, dynamic>.from(p);
          if (map['tiene_foto'] == 1) {
            map['foto'] = '/api/producto/${map['id_producto']}/foto';
          }
          resProds.add(map);
        }

        final payload = jsonEncode({
          'categorias': cats,
          'productos': resProds,
          'promociones': listasPromos,
        });
        L1Cache.productosJson = payload;
        return _jsonRaw(payload);
      } catch (e) {
        return _error('Error al listar productos: $e', statusCode: 500);
      }
    });

    // 8. GET /api/producto/:id/foto
    router.get('/api/producto/<id>/foto', (Request req, String id) async {
      try {
        final prId = int.tryParse(id) ?? 0;
        if (prId <= 0) return Response.notFound('ID no válido');

        final cacheKey = 'p_$prId';
        if (_fotoCache.containsKey(cacheKey)) {
          final cached = _fotoCache[cacheKey]!;
          return Response.ok(cached.$2, headers: {
            'Content-Type': cached.$1,
            'Cache-Control': 'public, max-age=31536000, immutable',
          });
        }

        final db = await _getDb();
        final res = await db.rawQuery('SELECT foto FROM producto WHERE id_producto = ?', [prId]);
        if (res.isNotEmpty && res.first['foto'] != null) {
          final dato = res.first['foto'] as String;
          final corte = dato.indexOf(';base64,');
          if (corte != -1) {
            final tipo = dato.substring(5, corte);
            final bytes = base64Decode(dato.substring(corte + 8));
            _fotoCache[cacheKey] = (tipo, bytes);
            return Response.ok(bytes, headers: {
              'Content-Type': tipo,
              'Cache-Control': 'public, max-age=31536000, immutable',
            });
          }
        }
        return Response.notFound('Foto no encontrada');
      } catch (e) {
        return Response.internalServerError(body: 'Error al servir foto: $e');
      }
    });

    // 8b. GET /api/promocion/:id/foto
    router.get('/api/promocion/<id>/foto', (Request req, String id) async {
      try {
        final prId = int.tryParse(id) ?? 0;
        if (prId <= 0) return Response.notFound('ID no válido');

        final cacheKey = 'promo_$prId';
        if (_fotoCache.containsKey(cacheKey)) {
          final cached = _fotoCache[cacheKey]!;
          return Response.ok(cached.$2, headers: {
            'Content-Type': cached.$1,
            'Cache-Control': 'public, max-age=31536000, immutable',
          });
        }

        final db = await _getDb();
        final res = await db.rawQuery('SELECT foto FROM promocion WHERE id_promocion = ?', [prId]);
        if (res.isNotEmpty && res.first['foto'] != null) {
          final dato = res.first['foto'] as String;
          final corte = dato.indexOf(';base64,');
          if (corte != -1) {
            final tipo = dato.substring(5, corte);
            final bytes = base64Decode(dato.substring(corte + 8));
            _fotoCache[cacheKey] = (tipo, bytes);
            return Response.ok(bytes, headers: {
              'Content-Type': tipo,
              'Cache-Control': 'public, max-age=31536000, immutable',
            });
          }
        }
        return Response.notFound('Foto no encontrada');
      } catch (e) {
        return Response.internalServerError(body: 'Error al servir foto: $e');
      }
    });

    // =========================================================================
    // 9. POST /api/comanda (ALTA VELOCIDAD Y ULTRA ESTABLE PARA ALTO VOLUMEN)
    // Serializado estrictamente mediante AsyncMutex para cero colisiones SQLite
    // =========================================================================
    router.post('/api/comanda', (Request req) async {
      try {
        final body = await _readJson(req);
        if (body.isEmpty) return _error('Datos de comanda requeridos', statusCode: 400);

        final db = await _getDb();

        int idCajero = body['id_cajero'] is int ? body['id_cajero'] as int : (int.tryParse(body['id_cajero']?.toString() ?? '') ?? 0);
        int? idMesero = body['id_mesero'] is int ? body['id_mesero'] as int : int.tryParse(body['id_mesero']?.toString() ?? '');
        int idBarra = body['id_barra'] is int ? body['id_barra'] as int : (int.tryParse(body['id_barra']?.toString() ?? '') ?? 0);
        int idEvento = body['id_evento'] is int ? body['id_evento'] as int : (int.tryParse(body['id_evento']?.toString() ?? '') ?? 0);

        // Validar barra existente (evitar Foreign Key constraint failed code 787)
        final barraRow = await db.rawQuery('SELECT id_barra, id_evento FROM barra WHERE id_barra = ? LIMIT 1', [idBarra]);
        if (barraRow.isEmpty) {
          final defBarra = await db.rawQuery('SELECT id_barra, id_evento FROM barra ORDER BY id_barra LIMIT 1');
          if (defBarra.isNotEmpty) {
            idBarra = defBarra.first['id_barra'] as int;
            if (idEvento <= 0) {
              idEvento = defBarra.first['id_evento'] as int;
            }
          } else {
            idBarra = 3;
          }
        }

        // Validar evento existente
        if (idEvento <= 0) {
          final defEvento = await db.rawQuery('SELECT id_evento FROM evento ORDER BY id_evento LIMIT 1');
          idEvento = defEvento.isNotEmpty ? (defEvento.first['id_evento'] as int) : 1;
        }

        // Validar cajero existente
        final cajRow = await db.rawQuery('SELECT id_cajero FROM cajero WHERE id_cajero = ? LIMIT 1', [idCajero]);
        if (cajRow.isEmpty) {
          final defCaj = await db.rawQuery('SELECT id_cajero FROM cajero WHERE activo = 1 ORDER BY id_cajero LIMIT 1');
          idCajero = defCaj.isNotEmpty ? (defCaj.first['id_cajero'] as int) : 1;
        }

        // Validar mesero si fue proporcionado (si no existe en BD, permitir null para no abortar la comanda)
        if (idMesero != null && idMesero > 0) {
          final mesRow = await db.rawQuery('SELECT id_mesero FROM mesero WHERE id_mesero = ? LIMIT 1', [idMesero]);
          if (mesRow.isEmpty) {
            idMesero = null;
          }
        } else {
          idMesero = null;
        }

        final items = (body['items'] as List? ?? []);
        final rawPromos = (body['promociones'] as List? ?? []);
        final pagos = (body['pagos'] as List? ?? (body['metodos_pago'] as List? ?? []));
        final totalDeclarado = (body['total'] is num) ? (body['total'] as num).toDouble() : 0.0;
        final claveIdempotencia = body['clave_idempotencia']?.toString();
        final observaciones = (body['observaciones'] ?? '').toString();

        // 1. Failsafe Idempotente: Si la tablet reintenta por red lenta, devolver la comanda ya creada
        if (claveIdempotencia != null && claveIdempotencia.isNotEmpty) {
          final existente = await db.rawQuery(
            'SELECT id_comanda, total FROM comanda WHERE clave_idempotencia = ? LIMIT 1',
            <String>[claveIdempotencia],
          );
          if (existente.isNotEmpty) {
            final comanda = existente.first;
            final comId = comanda['id_comanda'] as int;

            final lineas = await db.rawQuery('''
              SELECT d.id_detalle, d.id_producto, d.cantidad, d.precio_unitario, d.subtotal,
                     d.id_detalle_padre, d.id_promocion, p.nombre
              FROM detalle_comanda d
              LEFT JOIN producto p ON p.id_producto = d.id_producto
              WHERE d.id_comanda = ?
              ORDER BY d.id_detalle
            ''', [comId]);

            final hijos = <int, List<Map<String, dynamic>>>{};
            for (var l in lineas.where((l) => l['id_detalle_padre'] != null)) {
              final padreId = l['id_detalle_padre'] as int;
              hijos.putIfAbsent(padreId, () => []).add({
                'id_producto': l['id_producto'],
                'nombre': l['nombre'],
                'cantidad': l['cantidad'],
              });
            }

            final itemsFinales = lineas.where((l) => l['id_detalle_padre'] == null).map((l) {
              final detId = l['id_detalle'] as int;
              return {
                'id_producto': l['id_producto'],
                'nombre': l['nombre'],
                'cantidad': l['cantidad'],
                'precio_unitario': l['precio_unitario'],
                'subtotal': l['subtotal'],
                'acompanantes': hijos[detId] ?? [],
                'id_promocion': l['id_promocion'],
              };
            }).toList();

            return _json({
              'success': true,
              'repetida': true,
              'id_comanda': comId,
              'ref_comanda': comId.toString(),
              'total': comanda['total'],
              'items': itemsFinales,
              'promociones': rawPromos,
              'mensaje': 'Comanda previamente procesada (idempotente)'
            });
          }
        }

        final now = DatabaseHelper.nowSql();
        int idComanda = 0;
        double totalCalculado = 0.0;
        final List<Map<String, dynamic>> itemsParaTicket = [];
        final List<Map<String, dynamic>> paquetesVendidos = [];

        // 2. Transacción ACID totalmente atómica y serializada
        await _withTransaction((txn) async {
          // Validar cortesía de mesero o comanda
          int esCortesia = (body['es_cortesia'] == 1 || body['es_cortesia'] == true) ? 1 : 0;
          if (idMesero != null && esCortesia == 0) {
            final mesRow = await txn.rawQuery('SELECT es_cortesia FROM mesero WHERE id_mesero = ?', [idMesero]);
            if (mesRow.isNotEmpty && (mesRow.first['es_cortesia'] == 1 || mesRow.first['es_cortesia'] == true)) {
              esCortesia = 1;
            }
          }

          idComanda = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, id_mesero, fecha_hora, total, estado_pago, estatus, observaciones, clave_idempotencia, es_cortesia)
            VALUES (?, ?, ?, ?, ?, ?, 'PAGADO', 'COMPLETADO', ?, ?, ?)
          ''', [idEvento, idBarra, idCajero, idMesero, now, totalDeclarado, observaciones, claveIdempotencia, esCortesia]);

          // A) Procesar productos regulares
          for (var item in items) {
            if (item is! Map) continue;
            final idProd = item['id_producto'] is int ? item['id_producto'] as int : int.tryParse(item['id_producto']?.toString() ?? '');
            final qty = item['cantidad'] is int ? item['cantidad'] as int : (int.tryParse(item['cantidad']?.toString() ?? '1') ?? 1);
            final pu = (item['precio_unitario'] is num) ? (item['precio_unitario'] as num).toDouble() : 0.0;
            final subtotal = (item['subtotal'] is num) ? (item['subtotal'] as num).toDouble() : (pu * qty);
            final idPadre = item['id_detalle_padre'] is int ? item['id_detalle_padre'] as int : int.tryParse(item['id_detalle_padre']?.toString() ?? '');

            totalCalculado += subtotal;

            final idDetalle = await txn.rawInsert('''
              INSERT INTO detalle_comanda (id_comanda, id_producto, cantidad, precio_unitario, subtotal, id_detalle_padre, id_promocion)
              VALUES (?, ?, ?, ?, ?, ?, NULL)
            ''', [idComanda, idProd, qty, pu, subtotal, idPadre]);

            String nombreProd = (item['nombre'] ?? '').toString();

            // Descuento de inventario (soporte para botellas vinculadas por vaso)
            if (idProd != null && idProd > 0) {
              final pRow = await txn.rawQuery('''
                SELECT id_producto, nombre, stock_actual, id_botella_vinculada, vasos_por_botella
                FROM producto WHERE id_producto = ?
              ''', [idProd]);

              if (pRow.isNotEmpty) {
                final pData = pRow.first;
                if (nombreProd.isEmpty) nombreProd = (pData['nombre'] ?? '').toString();
                final idBotella = pData['id_botella_vinculada'] is int ? pData['id_botella_vinculada'] as int : int.tryParse(pData['id_botella_vinculada']?.toString() ?? '');
                final vasosPorBotella = (pData['vasos_por_botella'] is num) ? (pData['vasos_por_botella'] as num).toDouble() : 10.0;

                if (idBotella != null && idBotella > 0) {
                  final botRow = await txn.rawQuery('SELECT id_producto, nombre, stock_actual FROM producto WHERE id_producto = ?', [idBotella]);
                  if (botRow.isNotEmpty) {
                    final botData = botRow.first;
                    final botStAnt = (botData['stock_actual'] is num) ? (botData['stock_actual'] as num).toDouble() : 0.0;
                    final botADeducir = double.parse((qty / (vasosPorBotella > 0 ? vasosPorBotella : 10.0)).toStringAsFixed(4));
                    final botStNuevo = double.parse(math.max(0.0, botStAnt - botADeducir).toStringAsFixed(4));

                    await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [botStNuevo, idBotella]);
                    await txn.rawInsert('''
                      INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                      VALUES (?, 1, 'SALIDA', ?, ?, ?, ?, ?)
                    ''', [idBotella, botADeducir, botStAnt, botStNuevo, 'Venta comanda #$idComanda ($qty vaso(s) de ${pData['nombre']} -$botADeducir bot.)', now]);
                  }
                } else {
                  final stAnt = (pData['stock_actual'] is num) ? (pData['stock_actual'] as num).toDouble() : 0.0;
                  final stNuevo = double.parse(math.max(0.0, stAnt - qty).toStringAsFixed(4));

                  await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [stNuevo, idProd]);
                  await txn.rawInsert('''
                    INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                    VALUES (?, 1, 'SALIDA', ?, ?, ?, ?, ?)
                  ''', [idProd, qty, stAnt, stNuevo, 'Venta Comanda #$idComanda', now]);
                }
              }
            }

            // Acompañantes
            final List acompList = [];
            if (item['acompanantes'] != null && item['acompanantes'] is List) {
              acompList.addAll(item['acompanantes'] as List);
            } else if (item['acompanante'] != null && item['acompanante'] is Map) {
              acompList.add(item['acompanante']);
            }

            final List<Map<String, dynamic>> acompTicketList = [];
            for (var ac in acompList) {
              if (ac is! Map) continue;
              final idAcompProd = ac['id_producto'] is int ? ac['id_producto'] as int : (int.tryParse(ac['id_producto']?.toString() ?? '0') ?? 0);
              if (idAcompProd > 0) {
                final qtyAcomp = (ac['cantidad'] is int) ? (ac['cantidad'] as int) : (int.tryParse(ac['cantidad']?.toString() ?? '1') ?? 1);
                final cantTotalAcomp = qtyAcomp * qty;
                String nombreAcomp = (ac['nombre'] ?? '').toString();

                await txn.rawInsert('''
                  INSERT INTO detalle_comanda (id_comanda, id_producto, cantidad, precio_unitario, subtotal, id_detalle_padre, id_promocion)
                  VALUES (?, ?, ?, 0.0, 0.0, ?, NULL)
                ''', [idComanda, idAcompProd, cantTotalAcomp, idDetalle]);

                final acRow = await txn.rawQuery('SELECT nombre, stock_actual FROM producto WHERE id_producto = ?', [idAcompProd]);
                if (acRow.isNotEmpty) {
                  if (nombreAcomp.isEmpty) nombreAcomp = (acRow.first['nombre'] ?? '').toString();
                  final acAnt = (acRow.first['stock_actual'] is num) ? (acRow.first['stock_actual'] as num).toDouble() : 0.0;
                  final acNuevo = double.parse(math.max(0.0, acAnt - cantTotalAcomp).toStringAsFixed(4));

                  await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [acNuevo, idAcompProd]);
                  await txn.rawInsert('''
                    INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                    VALUES (?, 1, 'SALIDA', ?, ?, ?, ?, ?)
                  ''', [idAcompProd, cantTotalAcomp, acAnt, acNuevo, 'Acompañante Comanda #$idComanda', now]);
                }

                acompTicketList.add({
                  'id_producto': idAcompProd,
                  'nombre': nombreAcomp,
                  'cantidad': cantTotalAcomp,
                });
              }
            }

            itemsParaTicket.add({
              'id_producto': idProd,
              'nombre': nombreProd,
              'cantidad': qty,
              'precio_unitario': pu,
              'subtotal': subtotal,
              'acompanantes': acompTicketList,
            });
          }

          // B) Procesar promociones / combos (descontar contenido y registrar en detalle)
          for (var pr in rawPromos) {
            if (pr is! Map) continue;
            final idPromo = pr['id_promocion'] is int ? pr['id_promocion'] as int : int.tryParse(pr['id_promocion']?.toString() ?? '');
            final cantPromo = pr['cantidad'] is int ? pr['cantidad'] as int : (int.tryParse(pr['cantidad']?.toString() ?? '1') ?? 1);
            if (idPromo == null || cantPromo <= 0) continue;

            final promoRow = await txn.rawQuery('SELECT id_promocion, nombre, precio, activa FROM promocion WHERE id_promocion = ?', [idPromo]);
            if (promoRow.isEmpty) continue;

            final promoData = promoRow.first;
            final nombrePromo = (promoData['nombre'] ?? '').toString();
            final precioPromo = (promoData['precio'] is num) ? (promoData['precio'] as num).toDouble() : 0.0;
            final subtotalPromo = double.parse((precioPromo * cantPromo).toStringAsFixed(2));
            totalCalculado += subtotalPromo;

            final contenidoRows = await txn.rawQuery('''
              SELECT pd.id_producto, pd.cantidad, p.nombre, p.precio_venta, p.stock_actual, p.id_botella_vinculada, p.vasos_por_botella
              FROM promocion_detalle pd
              JOIN producto p ON p.id_producto = pd.id_producto
              WHERE pd.id_promocion = ? AND p.activo = 1
              ORDER BY pd.id_detalle_promocion
            ''', [idPromo]);

            final List<Map<String, dynamic>> contenidoInfo = [];
            final List<Map<String, dynamic>> partesParaRepartir = [];

            for (var c in contenidoRows) {
              final idProdC = c['id_producto'] as int;
              final cantEnPromo = (c['cantidad'] is int) ? (c['cantidad'] as int) : (int.tryParse(c['cantidad']?.toString() ?? '1') ?? 1);
              final cantTotalDescontar = cantEnPromo * cantPromo;
              final nombreProdC = (c['nombre'] ?? '').toString();
              final precioCatalogo = (c['precio_venta'] is num) ? (c['precio_venta'] as num).toDouble() : 0.0;

              contenidoInfo.add({
                'id_producto': idProdC,
                'nombre': nombreProdC,
                'cantidad': cantTotalDescontar,
              });

              partesParaRepartir.add({
                'idProd': idProdC,
                'qty': cantTotalDescontar,
                'precioCatalogo': precioCatalogo,
                'nombre': nombreProdC,
              });

              // Descontar inventario de cada producto del combo
              final idBotella = c['id_botella_vinculada'] as int?;
              final vasosPorBotella = (c['vasos_por_botella'] is num) ? (c['vasos_por_botella'] as num).toDouble() : 10.0;

              if (idBotella != null && idBotella > 0) {
                final botRow = await txn.rawQuery('SELECT stock_actual, nombre FROM producto WHERE id_producto = ?', [idBotella]);
                if (botRow.isNotEmpty) {
                  final botStAnt = (botRow.first['stock_actual'] is num) ? (botRow.first['stock_actual'] as num).toDouble() : 0.0;
                  final botADeducir = double.parse((cantTotalDescontar / (vasosPorBotella > 0 ? vasosPorBotella : 10.0)).toStringAsFixed(4));
                  final botStNuevo = double.parse(math.max(0.0, botStAnt - botADeducir).toStringAsFixed(4));

                  await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [botStNuevo, idBotella]);
                  await txn.rawInsert('''
                    INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                    VALUES (?, 1, 'SALIDA', ?, ?, ?, ?, ?)
                  ''', [idBotella, botADeducir, botStAnt, botStNuevo, 'Venta comanda #$idComanda (Combo: $nombrePromo -$botADeducir bot.)', now]);
                }
              } else {
                final stAnt = (c['stock_actual'] is num) ? (c['stock_actual'] as num).toDouble() : 0.0;
                final stNuevo = double.parse(math.max(0.0, stAnt - cantTotalDescontar).toStringAsFixed(4));

                await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [stNuevo, idProdC]);
                await txn.rawInsert('''
                  INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                  VALUES (?, 1, 'SALIDA', ?, ?, ?, ?, ?)
                ''', [idProdC, cantTotalDescontar, stAnt, stNuevo, 'Venta comanda #$idComanda (Combo: $nombrePromo)', now]);
              }
            }

            // Distribuir el precio de la promoción entre los componentes
            final partesRepartidas = _repartirPrecioPaquete(partesParaRepartir, subtotalPromo);
            for (var r in partesRepartidas) {
              await txn.rawInsert('''
                INSERT INTO detalle_comanda (id_comanda, id_producto, cantidad, precio_unitario, subtotal, id_detalle_padre, id_promocion)
                VALUES (?, ?, ?, ?, ?, NULL, ?)
              ''', [idComanda, r['idProd'], r['qty'], r['precio'], r['subtotal'], idPromo]);

              itemsParaTicket.add({
                'id_producto': r['idProd'],
                'nombre': r['nombre'],
                'cantidad': r['qty'],
                'precio_unitario': r['precio'],
                'subtotal': r['subtotal'],
                'id_promocion': idPromo,
                'acompanantes': [],
              });
            }

            paquetesVendidos.add({
              'id_promocion': idPromo,
              'nombre': nombrePromo,
              'cantidad': cantPromo,
              'precio_unitario': precioPromo,
              'subtotal': subtotalPromo,
              'contenido': contenidoInfo,
            });
          }

          // Sincronizar montos finales con redondeo estricto al centavo
          totalCalculado = double.parse(totalCalculado.toStringAsFixed(2));
          final totalFinal = (totalDeclarado > 0 && (totalDeclarado - totalCalculado).abs() < 0.05)
              ? totalDeclarado
              : totalCalculado;

          // Garantizar que la comanda tenga el total exacto persistido en SQLite
          await txn.rawUpdate('UPDATE comanda SET total = ? WHERE id_comanda = ?', [totalFinal, idComanda]);

          // C) Pagos
          if (esCortesia == 1) {
            await txn.rawInsert('''
              INSERT INTO pago_comanda (id_comanda, id_metodo_pago, monto, fecha_hora, referencia, estado)
              VALUES (?, 8, ?, ?, 'CORTESIA', 'APROBADO')
            ''', [idComanda, totalFinal, now]);
          } else if (pagos.isNotEmpty) {
            for (var p in pagos) {
              if (p is! Map) continue;
              final rawIdMetodo = p['id_metodo_pago'];
              int idMetodo = rawIdMetodo is int ? rawIdMetodo : (int.tryParse(rawIdMetodo?.toString() ?? '') ?? 0);

              if (idMetodo <= 0) {
                final metodoNombre = (p['nombre_metodo'] ?? p['metodo'] ?? 'EFECTIVO').toString().toUpperCase();
                if (metodoNombre.contains('TARJETA')) { idMetodo = 2; }
                else if (metodoNombre.contains('QR')) { idMetodo = 3; }
                else if (metodoNombre.contains('TRANSFER')) { idMetodo = 4; }
                else if (metodoNombre.contains('CORTESIA')) { idMetodo = 8; }
                else { idMetodo = 1; }
              }

              // Validar que el método de pago exista en BD (evitar Foreign Key constraint failed)
              final metRow = await txn.rawQuery('SELECT id_metodo_pago FROM metodo_pago WHERE id_metodo_pago = ?', [idMetodo]);
              if (metRow.isEmpty) {
                idMetodo = 1;
              }

              final num? pMonto = (p['monto'] is num) ? (p['monto'] as num) : num.tryParse(p['monto']?.toString() ?? '');
              final monto = (pMonto != null && pMonto > 0) ? pMonto.toDouble() : totalFinal;
              final ref = p['referencia']?.toString();

              await txn.rawInsert('''
                INSERT INTO pago_comanda (id_comanda, id_metodo_pago, monto, fecha_hora, referencia, estado)
                VALUES (?, ?, ?, ?, ?, 'APROBADO')
              ''', [idComanda, idMetodo, monto, now, ref]);
            }
          } else {
            await txn.rawInsert('''
              INSERT INTO pago_comanda (id_comanda, id_metodo_pago, monto, fecha_hora, referencia, estado)
              VALUES (?, 1, ?, ?, NULL, 'APROBADO')
            ''', [idComanda, totalFinal, now]);
          }

          // D) Registro inicial de impresión
          try {
            await txn.rawInsert('''
              INSERT INTO impresion_comanda_cajero (id_comanda, id_cajero, id_mesero, fecha_hora_impresion, numero_copia)
              VALUES (?, ?, ?, ?, 1)
            ''', [idComanda, idCajero, idMesero, now]);
            await txn.rawInsert('''
              INSERT INTO impresion_comanda_mesero (id_comanda, id_cajero, id_mesero, fecha_hora_impresion, numero_copia)
              VALUES (?, ?, ?, ?, 1)
            ''', [idComanda, idCajero, idMesero, now]);
          } catch (_) {}
        });

        // Invalidar caché en memoria para refresco inmediato de inventario en todas las tablets
        L1Cache.invalidateStock();
        L1Cache.invalidateCatalog();

        final totalFinal = (totalDeclarado > 0 && (totalDeclarado - totalCalculado).abs() < 0.05)
            ? totalDeclarado
            : totalCalculado;

        return _json({
          'success': true,
          'id_comanda': idComanda,
          'ref_comanda': idComanda.toString(),
          'total': totalFinal,
          'fecha_hora': now,
          'items': itemsParaTicket,
          'promociones': paquetesVendidos,
        });
      } catch (e, st) {
        print('❌ Error en /api/comanda: $e\n$st');
        return _error('Error procesando venta: $e', statusCode: 500);
      }
    });

    // 10. POST /api/impresion (Auditoría de reimpresiones y copias de comanda)
    router.post('/api/impresion', (Request req) async {
      try {
        final body = await _readJson(req);
        final idComanda = body['id_comanda'] is int ? body['id_comanda'] as int : int.tryParse(body['id_comanda']?.toString() ?? '');
        final tipo = (body['tipo'] ?? 'cajero').toString().toLowerCase();
        final table = tipo == 'mesero' ? 'impresion_comanda_mesero' : 'impresion_comanda_cajero';

        if (idComanda == null) return _json({'success': false, 'message': 'ID comanda requerido'});

        final db = await _getDb();
        final now = DatabaseHelper.nowSql();

        int copia = 1;
        await _withTransaction((txn) async {
          final ultRow = await txn.rawQuery('SELECT COALESCE(MAX(numero_copia), 0) AS ultima FROM $table WHERE id_comanda = ?', [idComanda]);
          copia = ((ultRow.isNotEmpty ? (ultRow.first['ultima'] as num).toInt() : 0)) + 1;

          final comRow = await txn.rawQuery('SELECT id_cajero, id_mesero FROM comanda WHERE id_comanda = ?', [idComanda]);
          final idCajero = comRow.isNotEmpty ? comRow.first['id_cajero'] : body['id_cajero'];
          final idMesero = comRow.isNotEmpty ? comRow.first['id_mesero'] : body['id_mesero'];

          await txn.rawInsert('''
            INSERT INTO $table (id_comanda, fecha_hora_impresion, numero_copia, id_cajero, id_mesero)
            VALUES (?, ?, ?, ?, ?)
          ''', [idComanda, now, copia, idCajero, idMesero]);
        });

        return _json({
          'success': true,
          'numero_copia': copia,
          'reimpresion': copia > 1,
        });
      } catch (e) {
        return _json({'success': false, 'message': 'No se pudo registrar impresión: $e'});
      }
    });

    // 11. GET /api/admin/comandas
    router.get('/api/admin/comandas', (Request req) async {
      try {
        final db = await _getDb();
        final comandas = await db.rawQuery('''
          SELECT c.*,
                 COALESCE(c.es_cortesia, 0) AS es_cortesia,
                 COALESCE(cj.nombre, 'Cajero eliminado')  AS nombre_cajero,
                 COALESCE(m.nombre,  'Mesero eliminado')  AS nombre_mesero,
                 m.password AS mesero_pin,
                 m.usuario AS mesero_usuario,
                 COALESCE(m.es_cortesia, 0) AS mesero_es_cortesia,
                 COALESCE(b.nombre_barra, 'Barra eliminada') AS nombre_barra
          FROM comanda c
          LEFT JOIN cajero cj ON c.id_cajero = cj.id_cajero
          LEFT JOIN mesero m ON c.id_mesero = m.id_mesero
          LEFT JOIN barra b ON c.id_barra = b.id_barra
          ORDER BY c.id_comanda DESC
        ''');

        final allDetalles = await db.rawQuery('''
          SELECT dc.*, COALESCE(p.nombre, 'Producto eliminado') AS nombre_producto, pr.nombre AS nombre_promocion
          FROM detalle_comanda dc
          LEFT JOIN producto p ON dc.id_producto = p.id_producto
          LEFT JOIN promocion pr ON dc.id_promocion = pr.id_promocion
        ''');

        final allPagos = await db.rawQuery('''
          SELECT pc.*, COALESCE(mp.nombre, 'Método desconocido') AS nombre_metodo
          FROM pago_comanda pc
          LEFT JOIN metodo_pago mp ON pc.id_metodo_pago = mp.id_metodo_pago
        ''');

        final Map<int, List<Map<String, dynamic>>> detallesPorComanda = {};
        for (var d in allDetalles) {
          final idC = d['id_comanda'] as int;
          detallesPorComanda.putIfAbsent(idC, () => []).add(d);
        }

        final Map<int, List<Map<String, dynamic>>> pagosPorComanda = {};
        for (var p in allPagos) {
          final idC = p['id_comanda'] as int;
          pagosPorComanda.putIfAbsent(idC, () => []).add(p);
        }

        final List<Map<String, dynamic>> res = [];
        for (var c in comandas) {
          final idCom = c['id_comanda'] as int;
          final dList = detallesPorComanda[idCom] ?? [];
          final pList = pagosPorComanda[idCom] ?? [];

          final map = Map<String, dynamic>.from(c);
          map['detalles'] = dList;
          map['items'] = dList;
          map['pagos'] = pList;
          res.add(map);
        }

        return _json(res);
      } catch (e) {
        return _error('Error listando comandas: $e', statusCode: 500);
      }
    });

    // 12. POST /api/admin/comandas/anular (con body JSON)
    router.post('/api/admin/comandas/anular', (Request req) async {
      try {
        final body = await _readJson(req);
        final idComanda = body['id_comanda'] is int ? body['id_comanda'] as int : int.tryParse(body['id_comanda']?.toString() ?? '');
        final motivo = (body['motivo_anulacion'] ?? body['motivo'] ?? 'Anulación administrativa').toString();
        final idAdmin = body['id_admin'] is int ? body['id_admin'] as int : (int.tryParse(body['id_admin']?.toString() ?? '1') ?? 1);

        if (idComanda == null) return _error('ID comanda requerido');
        return await _ejecutarAnulacionComanda(idComanda: idComanda, idAdmin: idAdmin, motivo: motivo);
      } catch (e) {
        return _error('Error al anular comanda: $e', statusCode: 500);
      }
    });

    // 12b. POST /api/admin/comandas/<id>/anular (con parámetro de ruta)
    router.post('/api/admin/comandas/<id>/anular', (Request req, String id) async {
      try {
        final idComanda = int.tryParse(id);
        if (idComanda == null) return _error('ID comanda inválido');

        Map<String, dynamic> body = {};
        try {
          body = await _readJson(req);
        } catch (_) {}

        final motivo = (body['motivo_anulacion'] ?? body['motivo'] ?? 'Anulación administrativa').toString();
        final idAdmin = body['id_admin'] is int ? body['id_admin'] as int : (int.tryParse(body['id_admin']?.toString() ?? '1') ?? 1);

        return await _ejecutarAnulacionComanda(idComanda: idComanda, idAdmin: idAdmin, motivo: motivo);
      } catch (e) {
        return _error('Error al anular comanda: $e', statusCode: 500);
      }
    });

    // 13. GET /api/admin/personal
    router.get('/api/admin/personal', (Request req) async {
      if (L1Cache.personalJson != null) {
        return _jsonRaw(L1Cache.personalJson!);
      }
      try {
        final db = await _getDb();
        final cajeros = await db.rawQuery('''
          SELECT c.id_cajero, c.id_barra, c.nombre, c.usuario, c.activo,
                 COALESCE(b.nombre_barra, 'Graderias') AS nombre_barra,
                 COALESCE(b.nombre_barra, 'Graderias') AS barra,
                 (SELECT COUNT(*) FROM mesero m WHERE m.id_cajero = c.id_cajero AND m.activo = 1) AS meseros,
                 (SELECT COUNT(*) FROM comanda k WHERE k.id_cajero = c.id_cajero) AS comandas
          FROM cajero c
          LEFT JOIN barra b ON b.id_barra = c.id_barra
          WHERE c.activo = 1
          ORDER BY c.nombre
        ''');

        final meseros = await db.rawQuery('''
          SELECT m.id_mesero, m.nombre, m.usuario, m.password AS pin, m.activo, m.id_cajero,
                 COALESCE(m.es_cortesia, 0) AS es_cortesia,
                 c.nombre AS cajero,
                 (SELECT COUNT(*) FROM comanda k WHERE k.id_mesero = m.id_mesero) AS comandas
          FROM mesero m
          LEFT JOIN cajero c ON c.id_cajero = m.id_cajero
          WHERE m.activo = 1
          ORDER BY m.nombre
        ''');

        final encargados = await db.rawQuery('''
          SELECT a.id_admin, a.nombre, a.usuario, a.rol, a.activo,
                 (SELECT COUNT(*) FROM movimiento_stock ms WHERE ms.id_admin = a.id_admin) AS movimientos
          FROM administrador_evento a
          WHERE a.activo = 1
          ORDER BY a.nombre
        ''');

        final payload = jsonEncode({
          'cajeros': cajeros,
          'meseros': meseros,
          'encargados': encargados,
        });
        L1Cache.personalJson = payload;
        return _jsonRaw(payload);
      } catch (e) {
        return _error('Error consultando personal: $e', statusCode: 500);
      }
    });

    // 14. POST /api/admin/cajeros
    router.post('/api/admin/cajeros', (Request req) async {
      try {
        final body = await _readJson(req);
        final nombre = (body['nombre'] ?? '').toString().trim();
        final usuario = (body['usuario'] ?? '').toString().trim();
        final password = (body['password'] ?? '').toString().trim();
        int idBarra = body['id_barra'] is int ? body['id_barra'] as int : (int.tryParse(body['id_barra']?.toString() ?? '') ?? 0);

        if (nombre.isEmpty) return _error('El nombre del cajero no puede estar vacío.', statusCode: 400);
        if (usuario.isEmpty) return _error('El usuario no puede estar vacío.', statusCode: 400);

        final db = await _getDb();

        // Validar barra existente en BD para garantizar integridad de Foreign Key
        final bCheck = await db.rawQuery('SELECT id_barra, nombre_barra FROM barra WHERE id_barra = ? LIMIT 1', [idBarra]);
        if (bCheck.isEmpty) {
          final defBarra = await db.rawQuery('SELECT id_barra, nombre_barra FROM barra ORDER BY id_barra LIMIT 1');
          idBarra = defBarra.isNotEmpty ? (defBarra.first['id_barra'] as int) : 3;
        }

        // Si existe un cajero inactivo con ese usuario, liberar el usuario
        try {
          await db.rawUpdate("UPDATE cajero SET usuario = usuario || '_retirado_' || id_cajero WHERE usuario = ? AND activo = 0", [usuario]);
        } catch (_) {}

        // Comprobar si ya existe otro cajero activo con ese usuario
        final dup = await db.rawQuery('SELECT id_cajero FROM cajero WHERE usuario = ? AND activo = 1', [usuario]);
        if (dup.isNotEmpty) {
          return _error('Ese nombre de usuario ya está registrado por otro cajero.', statusCode: 400);
        }

        final id = await _writeMutex.run(() async {
          return await db.rawInsert('''
            INSERT INTO cajero (id_barra, nombre, usuario, password, activo)
            VALUES (?, ?, ?, ?, 1)
          ''', [idBarra, nombre, usuario, password]);
        });

        return _json({'success': true, 'id_cajero': id, 'message': 'Cajero registrado con éxito'});
      } catch (e) {
        return _error('Error al crear cajero: $e');
      }
    });

    // 14b. PUT /api/admin/cajeros/:id (EDITAR CAJERO)
    router.put('/api/admin/cajeros/<id>', (Request req, String id) async {
      try {
        final cId = int.tryParse(id) ?? 0;
        if (cId <= 0) return _error('Cajero no válido', statusCode: 400);

        final body = await _readJson(req);
        final db = await _getDb();

        final rows = await db.rawQuery('SELECT * FROM cajero WHERE id_cajero = ?', [cId]);
        if (rows.isEmpty) return _error('Ese cajero ya no existe.', statusCode: 404);
        final caj = rows.first;

        final nuevoNombre = (body['nombre'] ?? caj['nombre']).toString().trim();
        final nuevoUsuario = (body['usuario'] ?? caj['usuario']).toString().trim();
        final nuevoPass = (body['password'] != null && body['password'].toString().trim().isNotEmpty)
            ? body['password'].toString().trim()
            : caj['password'];
        final nuevoActivo = body['activo'] != null ? ((body['activo'] == true || body['activo'] == 1) ? 1 : 0) : caj['activo'];

        int idBarra = body['id_barra'] is int ? body['id_barra'] as int : (int.tryParse(body['id_barra']?.toString() ?? '') ?? (caj['id_barra'] as int? ?? 3));
        final bCheck = await db.rawQuery('SELECT id_barra FROM barra WHERE id_barra = ? LIMIT 1', [idBarra]);
        if (bCheck.isEmpty) {
          idBarra = (caj['id_barra'] as int?) ?? 3;
        }

        if (nuevoNombre.isEmpty) return _error('El nombre no puede estar vacío.', statusCode: 400);
        if (nuevoUsuario.isEmpty) return _error('El usuario no puede estar vacío.', statusCode: 400);

        final dup = await db.rawQuery('SELECT id_cajero FROM cajero WHERE usuario = ? AND id_cajero != ? AND activo = 1', [nuevoUsuario, cId]);
        if (dup.isNotEmpty) {
          return _error('Ese nombre de usuario ya está en uso por otro cajero.', statusCode: 400);
        }

        await _writeMutex.run(() async {
          await db.rawUpdate('''
            UPDATE cajero SET id_barra = ?, nombre = ?, usuario = ?, password = ?, activo = ? WHERE id_cajero = ?
          ''', [idBarra, nuevoNombre, nuevoUsuario, nuevoPass, nuevoActivo, cId]);
        });

        return _json({'success': true, 'message': 'Cajero "$nuevoNombre" actualizado.'});
      } catch (e) {
        return _error('Error al actualizar cajero: $e', statusCode: 500);
      }
    });

    // 15. DELETE /api/admin/cajeros/:id
    router.delete('/api/admin/cajeros/<id>', (Request req, String id) async {
      try {
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE cajero SET activo = 0 WHERE id_cajero = ?', [int.tryParse(id) ?? 0]);
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error al desactivar cajero: $e', statusCode: 500);
      }
    });

    // 16. POST /api/admin/meseros
    router.post('/api/admin/meseros', (Request req) async {
      try {
        final body = await _readJson(req);
        final nombre = (body['nombre'] ?? '').toString().trim();
        final usuario = (body['usuario'] ?? '').toString().trim();
        final pin = (body['password'] ?? body['pin'] ?? '').toString().trim();
        int idCajero = body['id_cajero'] is int ? body['id_cajero'] as int : (int.tryParse(body['id_cajero']?.toString() ?? '') ?? 0);

        if (nombre.isEmpty) return _error('El nombre del mesero no puede estar vacío.', statusCode: 400);
        if (pin.isEmpty) return _error('El PIN no puede estar vacío.', statusCode: 400);

        final db = await _getDb();

        // Validar cajero existente para foreign key
        final cCheck = await db.rawQuery('SELECT id_cajero FROM cajero WHERE id_cajero = ? LIMIT 1', [idCajero]);
        if (cCheck.isEmpty) {
          final defCaj = await db.rawQuery('SELECT id_cajero FROM cajero WHERE activo = 1 ORDER BY id_cajero LIMIT 1');
          idCajero = defCaj.isNotEmpty ? (defCaj.first['id_cajero'] as int) : 1;
        }

        // Validar evento existente para foreign key
        int idEvento = 1;
        final defEvt = await db.rawQuery('SELECT id_evento FROM evento ORDER BY id_evento LIMIT 1');
        if (defEvt.isNotEmpty) {
          idEvento = defEvt.first['id_evento'] as int;
        }

        // Comprobar si ya existe otro mesero activo con ese PIN
        final dup = await db.rawQuery('SELECT id_mesero FROM mesero WHERE password = ? AND activo = 1', [pin]);
        if (dup.isNotEmpty) {
          return _error('Ese PIN ya está en uso por otro mesero activo.', statusCode: 400);
        }

        final id = await _writeMutex.run(() async {
          return await db.rawInsert('''
            INSERT INTO mesero (id_evento, id_cajero, nombre, usuario, password, activo, es_cortesia)
            VALUES (?, ?, ?, ?, ?, 1, 0)
          ''', [idEvento, idCajero, nombre, usuario, pin]);
        });
        return _json({'success': true, 'id_mesero': id, 'message': 'Mesero registrado con éxito'});
      } catch (e) {
        return _error('Error al crear mesero: $e');
      }
    });

    // 16b. PUT /api/admin/meseros/:id (EDITAR MESERO)
    router.put('/api/admin/meseros/<id>', (Request req, String id) async {
      try {
        final mId = int.tryParse(id) ?? 0;
        if (mId <= 0) return _error('Mesero no válido', statusCode: 400);

        final body = await _readJson(req);
        final db = await _getDb();

        final rows = await db.rawQuery('SELECT * FROM mesero WHERE id_mesero = ?', [mId]);
        if (rows.isEmpty) return _error('Ese mesero ya no existe.', statusCode: 404);
        final mes = rows.first;

        final nuevoNombre = (body['nombre'] ?? mes['nombre']).toString().trim();
        final nuevoUsuario = (body['usuario'] ?? mes['usuario'] ?? '').toString().trim();
        final nuevoPin = (body['password'] ?? body['pin'] ?? mes['password']).toString().trim();
        int nuevoCajero = body['id_cajero'] is int ? body['id_cajero'] as int : (int.tryParse(body['id_cajero']?.toString() ?? '') ?? (mes['id_cajero'] as int? ?? 1));
        final cCheck = await db.rawQuery('SELECT id_cajero FROM cajero WHERE id_cajero = ? LIMIT 1', [nuevoCajero]);
        if (cCheck.isEmpty) {
          nuevoCajero = (mes['id_cajero'] as int?) ?? 1;
        }
        final nuevoActivo = body['activo'] != null ? ((body['activo'] == true || body['activo'] == 1) ? 1 : 0) : mes['activo'];
        final nuevoCortesia = body['es_cortesia'] != null ? ((body['es_cortesia'] == true || body['es_cortesia'] == 1) ? 1 : 0) : (mes['es_cortesia'] ?? 0);

        if (nuevoNombre.isEmpty) return _error('El nombre no puede estar vacío.', statusCode: 400);
        if (nuevoPin.isEmpty) return _error('El PIN no puede estar vacío.', statusCode: 400);

        if (nuevoActivo == 1) {
          final dup = await db.rawQuery('SELECT id_mesero FROM mesero WHERE password = ? AND activo = 1 AND id_mesero != ?', [nuevoPin, mId]);
          if (dup.isNotEmpty) {
            return _error('Ese PIN ya está en uso por otro mesero activo.', statusCode: 400);
          }
        }

        await _writeMutex.run(() async {
          await db.rawUpdate('''
            UPDATE mesero SET nombre = ?, usuario = ?, password = ?, id_cajero = ?, activo = ?, es_cortesia = ? WHERE id_mesero = ?
          ''', [nuevoNombre, nuevoUsuario, nuevoPin, nuevoCajero, nuevoActivo, nuevoCortesia, mId]);
        });

        return _json({'success': true, 'message': 'Mesero "$nuevoNombre" actualizado.'});
      } catch (e) {
        return _error('Error al actualizar mesero: $e', statusCode: 500);
      }
    });

    // 17. DELETE /api/admin/meseros/:id
    router.delete('/api/admin/meseros/<id>', (Request req, String id) async {
      try {
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE mesero SET activo = 0 WHERE id_mesero = ?', [int.tryParse(id) ?? 0]);
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error al desactivar mesero: $e', statusCode: 500);
      }
    });

    // 18. GET /api/admin/catalogo
    router.get('/api/admin/catalogo', (Request req) async {
      try {
        final db = await _getDb();
        final cats = await db.rawQuery('''
          SELECT c.id_categoria, c.nombre, c.descripcion, c.tipo, c.activo, COALESCE(c.orden, 0) AS orden,
                 (SELECT COUNT(*) FROM producto p WHERE p.id_categoria = c.id_categoria AND p.activo = 1) AS productos
            FROM categoria_producto c ORDER BY c.orden ASC, c.id_categoria ASC
        ''');

        final prods = await db.rawQuery('''
          SELECT p.id_producto, p.nombre, p.precio_venta, p.stock_actual, p.activo, COALESCE(p.orden, 0) AS orden,
                 p.id_categoria, c.nombre AS categoria, COALESCE(c.orden, 0) AS cat_orden,
                 COALESCE(p.requiere_acompanante, 0) AS requiere_acompanante,
                 COALESCE(p.es_acompanante, 0) AS es_acompanante,
                 p.id_botella_vinculada, COALESCE(p.vasos_por_botella, 10) AS vasos_por_botella,
                 CASE WHEN p.foto IS NULL OR p.foto = '' THEN 0 ELSE 1 END AS tiene_foto,
                 LENGTH(COALESCE(p.foto, '')) AS foto_v,
                 (SELECT COUNT(*) FROM detalle_comanda d WHERE d.id_producto = p.id_producto) AS vendido
            FROM producto p
            LEFT JOIN categoria_producto c ON c.id_categoria = p.id_categoria
           ORDER BY c.orden ASC, c.nombre, p.orden ASC, p.id_producto ASC
        ''');

        final List<Map<String, dynamic>> resProds = [];
        for (var p in prods) {
          final map = Map<String, dynamic>.from(p);
          if (map['tiene_foto'] == 1) {
            map['foto'] = '/api/producto/${map['id_producto']}/foto';
          }
          resProds.add(map);
        }

        return _json({'categorias': cats, 'productos': resProds});
      } catch (e) {
        return _error('Error al consultar catálogo: $e', statusCode: 500);
      }
    });

    // 19. POST /api/admin/categorias
    router.post('/api/admin/categorias', (Request req) async {
      try {
        final body = await _readJson(req);
        final nombre = body['nombre'] ?? '';
        final desc = body['descripcion'] ?? '';
        final tipo = body['tipo'] ?? 'BEBIDA';

        final db = await _getDb();
        final now = DatabaseHelper.nowSql();
        final id = await _writeMutex.run(() async {
          return await db.rawInsert('''
            INSERT INTO categoria_producto (nombre, descripcion, tipo, orden, activo, creada_en)
            VALUES (?, ?, ?, 1, 1, ?)
          ''', [nombre, desc, tipo, now]);
        });
        return _json({'success': true, 'id_categoria': id, 'message': 'Categoría creada'});
      } catch (e) {
        return _error('Error al crear categoría: $e');
      }
    });

    // 19b. PUT /api/admin/categorias/:id (EDITAR CATEGORÍA)
    router.put('/api/admin/categorias/<id>', (Request req, String id) async {
      try {
        final catId = int.tryParse(id) ?? 0;
        if (catId <= 0) return _error('Categoría no válida', statusCode: 400);

        final body = await _readJson(req);
        final db = await _getDb();

        final rows = await db.rawQuery('SELECT * FROM categoria_producto WHERE id_categoria = ?', [catId]);
        if (rows.isEmpty) return _error('Esa categoría ya no existe.', statusCode: 404);
        final cat = rows.first;

        final nuevoNombre = (body['nombre'] ?? cat['nombre']).toString().trim();
        final nuevaDesc = (body['descripcion'] ?? cat['descripcion'] ?? '').toString().trim();
        final nuevoTipo = (body['tipo'] ?? cat['tipo'] ?? 'BEBIDA').toString().trim();
        final nuevoActivo = body['activo'] != null ? ((body['activo'] == true || body['activo'] == 1) ? 1 : 0) : cat['activo'];

        if (nuevoNombre.isEmpty) return _error('La categoría necesita un nombre.', statusCode: 400);

        await _writeMutex.run(() async {
          await db.rawUpdate('''
            UPDATE categoria_producto SET nombre = ?, descripcion = ?, tipo = ?, activo = ? WHERE id_categoria = ?
          ''', [nuevoNombre, nuevaDesc, nuevoTipo, nuevoActivo, catId]);
        });

        return _json({'success': true, 'message': 'Categoría "$nuevoNombre" actualizada.'});
      } catch (e) {
        return _error('Error al actualizar categoría: $e', statusCode: 500);
      }
    });

    // 20. DELETE /api/admin/categorias/:id
    router.delete('/api/admin/categorias/<id>', (Request req, String id) async {
      try {
        final db = await _getDb();
        final idCat = int.tryParse(id) ?? 0;
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE categoria_producto SET activo = 0 WHERE id_categoria = ?', [idCat]);
        });
        return _json({'success': true, 'message': 'Categoría eliminada'});
      } catch (e) {
        return _error('Error al desactivar categoría: $e', statusCode: 500);
      }
    });

    // 21. POST /api/admin/productos
    router.post('/api/admin/productos', (Request req) async {
      try {
        final body = await _readJson(req);
        int idCat = body['id_categoria'] is int ? body['id_categoria'] as int : (int.tryParse(body['id_categoria']?.toString() ?? '') ?? 0);
        final nombre = (body['nombre'] ?? '').toString();
        final desc = (body['descripcion'] ?? '').toString();
        final tipo = (body['tipo_producto'] ?? 'BEBIDA').toString();
        final precio = (body['precio_venta'] is num) ? (body['precio_venta'] as num).toDouble() : (double.tryParse(body['precio_venta']?.toString() ?? '0') ?? 0.0);
        final stock = (body['stock_actual'] is num) ? (body['stock_actual'] as num).toDouble() : (double.tryParse(body['stock_actual']?.toString() ?? '0') ?? 0.0);
        final reqAcomp = (body['requiere_acompanante'] == 1 || body['requiere_acompanante'] == true) ? 1 : 0;
        final stockAlerta = (body['stock_alerta'] is num) ? (body['stock_alerta'] as num).toInt() : (int.tryParse(body['stock_alerta']?.toString() ?? '5') ?? 5);
        final esBotella = (body['es_botella'] == 1 || body['es_botella'] == true) ? 1 : 0;
        final vasos = (body['vasos_por_botella'] is num) ? (body['vasos_por_botella'] as num).toDouble() : (double.tryParse(body['vasos_por_botella']?.toString() ?? '10') ?? 10.0);

        final db = await _getDb();
        if (idCat <= 0) {
          final defCat = await db.rawQuery('SELECT id_categoria FROM categoria_producto WHERE activo = 1 ORDER BY id_categoria LIMIT 1');
          idCat = defCat.isNotEmpty ? (defCat.first['id_categoria'] as int) : 1;
        }

        final now = DatabaseHelper.nowSql();

        int idProd = 0;
        await _withTransaction((txn) async {
          int validAdminId = 1;
          final aRow = await txn.rawQuery('SELECT id_admin FROM administrador_evento LIMIT 1');
          if (aRow.isNotEmpty) validAdminId = aRow.first['id_admin'] as int;

          idProd = await txn.rawInsert('''
            INSERT INTO producto (
              id_categoria, nombre, descripcion, tipo_producto, precio_venta,
              stock_actual, stock_alerta, requiere_acompanante, es_botella,
              vasos_por_botella, orden, activo, creado_en
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, ?)
          ''', [idCat, nombre, desc, tipo, precio, stock, stockAlerta, reqAcomp, esBotella, vasos, now]);

          if (stock > 0) {
            await txn.rawInsert('''
              INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
              VALUES (?, ?, 'INICIAL', ?, 0, ?, 'Stock inicial producto', ?)
            ''', [idProd, validAdminId, stock, stock, now]);
          }
        });

        L1Cache.invalidateCatalog();
        return _json({'success': true, 'id_producto': idProd, 'message': 'Producto creado'});
      } catch (e) {
        return _error('Error al crear producto: $e', statusCode: 500);
      }
    });

    // 22. PUT /api/admin/productos/:id
    router.put('/api/admin/productos/<id>', (Request req, String id) async {
      try {
        final pId = int.tryParse(id) ?? 0;
        if (pId <= 0) return _error('Producto no válido', statusCode: 400);

        final body = await _readJson(req);
        final idCat = body['id_categoria'];
        final nombre = body['nombre'];
        final desc = body['descripcion'];
        final tipo = body['tipo_producto'];
        final precio = (body['precio_venta'] is num) ? (body['precio_venta'] as num).toDouble() : null;
        final reqAcomp = body['requiere_acompanante'] != null ? ((body['requiere_acompanante'] == 1 || body['requiere_acompanante'] == true) ? 1 : 0) : null;
        final alerta = body['stock_alerta'];
        final esBotella = body['es_botella'] != null ? ((body['es_botella'] == 1 || body['es_botella'] == true) ? 1 : 0) : null;
        final vasos = body['vasos_por_botella'];

        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('''
            UPDATE producto SET
              id_categoria = COALESCE(?, id_categoria),
              nombre = COALESCE(?, nombre),
              descripcion = COALESCE(?, descripcion),
              tipo_producto = COALESCE(?, tipo_producto),
              precio_venta = COALESCE(?, precio_venta),
              requiere_acompanante = COALESCE(?, requiere_acompanante),
              stock_alerta = COALESCE(?, stock_alerta),
              es_botella = COALESCE(?, es_botella),
              vasos_por_botella = COALESCE(?, vasos_por_botella)
            WHERE id_producto = ?
          ''', [idCat, nombre, desc, tipo, precio, reqAcomp, alerta, esBotella, vasos, pId]);
        });

        L1Cache.invalidateCatalog();
        return _json({'success': true, 'message': 'Producto actualizado'});
      } catch (e) {
        return _error('Error al actualizar producto: $e', statusCode: 500);
      }
    });

    // 23. PUT /api/admin/productos/:id/acompanamiento
    router.put('/api/admin/productos/<id>/acompanamiento', (Request req, String id) async {
      try {
        final pId = int.tryParse(id) ?? 0;
        final body = await _readJson(req);
        final list = (body['acompanamientos'] as List? ?? []);

        await _withTransaction((txn) async {
          await txn.rawDelete('DELETE FROM producto_acompanamiento WHERE id_producto_principal = ?', [pId]);
          for (var a in list) {
            final idAcomp = a is int ? a : (int.tryParse(a.toString()) ?? 0);
            if (idAcomp > 0) {
              await txn.rawInsert('''
                INSERT INTO producto_acompanamiento (id_producto_principal, id_producto_acompanante)
                VALUES (?, ?)
              ''', [pId, idAcomp]);
            }
          }
        });

        return _json({'success': true, 'message': 'Acompañamientos actualizados'});
      } catch (e) {
        return _error('Error al guardar acompañamiento: $e', statusCode: 500);
      }
    });

    // 24. PUT /api/admin/productos/:id/foto
    router.put('/api/admin/productos/<id>/foto', (Request req, String id) async {
      try {
        final pId = int.tryParse(id) ?? 0;
        final body = await _readJson(req);
        final foto = body['foto'] as String?;

        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE producto SET foto = ? WHERE id_producto = ?', [foto, pId]);
        });
        _fotoCache.remove('p_$id');
        return _json({'success': true, 'message': 'Foto guardada'});
      } catch (e) {
        return _error('Error al guardar foto: $e', statusCode: 500);
      }
    });

    // 25. DELETE /api/admin/productos/:id
    router.delete('/api/admin/productos/<id>', (Request req, String id) async {
      try {
        final db = await _getDb();
        final pId = int.tryParse(id) ?? 0;
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE producto SET activo = 0 WHERE id_producto = ?', [pId]);
        });
        L1Cache.invalidateCatalog();
        return _json({'success': true, 'message': 'Producto eliminado'});
      } catch (e) {
        return _error('Error al eliminar producto: $e', statusCode: 500);
      }
    });

    // Estados rápidos (Toggle activo)
    router.put('/api/admin/cajeros/<id>/estado', (Request req, String id) async {
      try {
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE cajero SET activo = CASE WHEN activo = 1 THEN 0 ELSE 1 END WHERE id_cajero = ?', [int.tryParse(id) ?? 0]);
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error al cambiar estado: $e', statusCode: 500);
      }
    });

    router.put('/api/admin/meseros/<id>/estado', (Request req, String id) async {
      try {
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE mesero SET activo = CASE WHEN activo = 1 THEN 0 ELSE 1 END WHERE id_mesero = ?', [int.tryParse(id) ?? 0]);
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error al cambiar estado: $e', statusCode: 500);
      }
    });

    router.put('/api/admin/categorias/<id>/estado', (Request req, String id) async {
      try {
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE categoria_producto SET activo = CASE WHEN activo = 1 THEN 0 ELSE 1 END WHERE id_categoria = ?', [int.tryParse(id) ?? 0]);
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error al cambiar estado: $e', statusCode: 500);
      }
    });

    router.put('/api/admin/productos/<id>/estado', (Request req, String id) async {
      try {
        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE producto SET activo = CASE WHEN activo = 1 THEN 0 ELSE 1 END WHERE id_producto = ?', [int.tryParse(id) ?? 0]);
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error al cambiar estado: $e', statusCode: 500);
      }
    });

    router.put('/api/admin/categorias/reordenar', (Request req) async {
      try {
        final body = await _readJson(req);
        final ordenes = body['ordenes'] as List? ?? [];
        await _withTransaction((txn) async {
          for (var o in ordenes) {
            if (o is Map) {
              await txn.rawUpdate('UPDATE categoria_producto SET orden = ? WHERE id_categoria = ?', [o['orden'], o['id']]);
            }
          }
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error reordenando categorías: $e', statusCode: 500);
      }
    });

    router.put('/api/admin/productos/reordenar', (Request req) async {
      try {
        final body = await _readJson(req);
        final ordenes = body['ordenes'] as List? ?? [];
        await _withTransaction((txn) async {
          for (var o in ordenes) {
            if (o is Map) {
              await txn.rawUpdate('UPDATE producto SET orden = ? WHERE id_producto = ?', [o['orden'], o['id']]);
            }
          }
        });
        return _json({'success': true});
      } catch (e) {
        return _error('Error reordenando productos: $e', statusCode: 500);
      }
    });

    // 26. GET /api/admin/promociones
    router.get('/api/admin/promociones', (Request req) async {
      try {
        final db = await _getDb();
        final promos = await db.rawQuery('SELECT * FROM promocion WHERE activa = 1');

        final List<Map<String, dynamic>> res = [];
        for (var p in promos) {
          final pId = p['id_promocion'] as int;
          final detalle = await db.rawQuery('''
            SELECT pd.*, pr.nombre AS producto_nombre
            FROM promocion_detalle pd
            JOIN producto pr ON pd.id_producto = pr.id_producto
            WHERE pd.id_promocion = ?
          ''', [pId]);

          final map = Map<String, dynamic>.from(p);
          map['items'] = detalle;
          if (map['foto'] != null && map['foto'].toString().isNotEmpty) {
            map['foto'] = '/api/promocion/$pId/foto';
          }
          res.add(map);
        }

        return _json({'promociones': res});
      } catch (e) {
        return _error('Error al leer promociones: $e', statusCode: 500);
      }
    });

    // 27. POST /api/admin/promociones
    router.post('/api/admin/promociones', (Request req) async {
      try {
        final body = await _readJson(req);
        final nombre = body['nombre'] ?? '';
        final desc = body['descripcion'] ?? '';
        final precio = (body['precio'] is num) ? (body['precio'] as num).toDouble() : 0.0;
        final contenido = (body['contenido'] as List? ?? []);

        final now = DatabaseHelper.nowSql();

        int idPromo = 0;
        await _withTransaction((txn) async {
          idPromo = await txn.rawInsert('''
            INSERT INTO promocion (nombre, descripcion, precio, activa, creada_por_admin, fecha_creacion)
            VALUES (?, ?, ?, 1, 1, ?)
          ''', [nombre, desc, precio, now]);

          for (var c in contenido) {
            if (c is! Map) continue;
            final idProd = c['id_producto'] is int ? c['id_producto'] as int : (int.tryParse(c['id_producto']?.toString() ?? '0') ?? 0);
            final qty = c['cantidad'] is int ? c['cantidad'] as int : (int.tryParse(c['cantidad']?.toString() ?? '1') ?? 1);
            if (idProd > 0 && qty > 0) {
              await txn.rawInsert('''
                INSERT INTO promocion_detalle (id_promocion, id_producto, cantidad) VALUES (?, ?, ?)
              ''', [idPromo, idProd, qty]);
            }
          }
        });

        L1Cache.invalidateCatalog();
        return _json({'success': true, 'id_promocion': idPromo, 'message': 'Promoción creada'});
      } catch (e) {
        return _error('Error al crear promoción: $e', statusCode: 500);
      }
    });

    // 28. PUT /api/admin/promociones/:id (EDITAR DETALLES PROMOCIÓN)
    router.put('/api/admin/promociones/<id>', (Request req, String id) async {
      try {
        final body = await _readJson(req);
        final pId = int.tryParse(id) ?? 0;
        final nombre = body['nombre'];
        final desc = body['descripcion'];
        final precio = (body['precio'] is num) ? (body['precio'] as num).toDouble() : null;
        final activa = body['activa'] == null ? 1 : ((body['activa'] == true || body['activa'] == 1) ? 1 : 0);
        final contenido = body['contenido'] as List?;

        await _withTransaction((txn) async {
          await txn.rawUpdate('''
            UPDATE promocion SET nombre = ?, descripcion = ?, precio = ?, activa = ? WHERE id_promocion = ?
          ''', [nombre, desc, precio, activa, pId]);

          if (contenido != null) {
            await txn.rawDelete('DELETE FROM promocion_detalle WHERE id_promocion = ?', [pId]);
            for (var c in contenido) {
              if (c is! Map) continue;
              final idProd = c['id_producto'] is int ? c['id_producto'] as int : (int.tryParse(c['id_producto']?.toString() ?? '0') ?? 0);
              final qty = c['cantidad'] is int ? c['cantidad'] as int : (int.tryParse(c['cantidad']?.toString() ?? '1') ?? 1);
              if (idProd > 0 && qty > 0) {
                await txn.rawInsert('''
                  INSERT INTO promocion_detalle (id_promocion, id_producto, cantidad) VALUES (?, ?, ?)
                ''', [pId, idProd, qty]);
              }
            }
          }
        });

        return _json({'success': true, 'message': 'Promoción actualizada'});
      } catch (e) {
        return _error('Error al actualizar promoción: $e', statusCode: 500);
      }
    });

    // 29. DELETE /api/admin/promociones/:id
    router.delete('/api/admin/promociones/<id>', (Request req, String id) async {
      try {
        final db = await _getDb();
        final pId = int.tryParse(id) ?? 0;
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE promocion SET activa = 0 WHERE id_promocion = ?', [pId]);
        });
        return _json({'success': true, 'message': 'Promoción eliminada'});
      } catch (e) {
        return _error('Error al eliminar promoción: $e', statusCode: 500);
      }
    });

    // 30. POST /api/admin/stock/movimiento (AJUSTE MANUAL DE STOCK)
    router.post('/api/admin/stock/movimiento', (Request req) async {
      try {
        final body = await _readJson(req);
        final idProd = body['id_producto'] is int ? body['id_producto'] as int : (int.tryParse(body['id_producto']?.toString() ?? '') ?? 0);
        final tipo = (body['tipo_movimiento'] ?? 'AJUSTE').toString().toUpperCase();
        final qty = body['cantidad'] is int ? body['cantidad'] as int : (int.tryParse(body['cantidad']?.toString() ?? '0') ?? 0);
        final motivo = (body['motivo'] ?? 'Ajuste manual de stock').toString();
        final idAdmin = body['id_admin'] is int ? body['id_admin'] as int : 1;

        if (idProd <= 0 || qty == 0) {
          return _error('Producto o cantidad no válida', statusCode: 400);
        }

        final now = DatabaseHelper.nowSql();
        num finalStock = 0;

        await _withTransaction((txn) async {
          final pRow = await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = ?', [idProd]);
          final stAnt = pRow.isNotEmpty ? ((pRow.first['stock_actual'] as num).toDouble()) : 0.0;
          double stNuevo = stAnt;

          if (tipo == 'ENTRADA' || tipo == 'COMPRA' || tipo == 'AJUSTE_POSITIVO') {
            stNuevo = stAnt + qty.abs();
          } else if (tipo == 'SALIDA' || tipo == 'MERMA' || tipo == 'AJUSTE_NEGATIVO') {
            stNuevo = math.max(0.0, stAnt - qty.abs());
          } else {
            stNuevo = qty.abs().toDouble();
          }

          stNuevo = double.parse(stNuevo.toStringAsFixed(4));
          finalStock = (stNuevo == stNuevo.roundToDouble()) ? stNuevo.toInt() : stNuevo;

          int validAdminId = idAdmin;
          final aCheck = await txn.rawQuery('SELECT id_admin FROM administrador_evento WHERE id_admin = ?', [idAdmin]);
          if (aCheck.isEmpty) {
            final aRow = await txn.rawQuery('SELECT id_admin FROM administrador_evento LIMIT 1');
            if (aRow.isNotEmpty) validAdminId = aRow.first['id_admin'] as int;
          }

          await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [stNuevo, idProd]);
          await txn.rawInsert('''
            INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ''', [idProd, validAdminId, tipo, qty, stAnt, stNuevo, motivo, now]);
        });

        L1Cache.invalidateStock();

        return _json({
          'success': true,
          'message': 'Stock actualizado con éxito',
          'stock_actual': finalStock,
          'stock_nuevo': finalStock,
        });
      } catch (e) {
        return _error('Error al actualizar stock: $e', statusCode: 500);
      }
    });

    // 31. GET /api/admin/productos/:id/movimientos
    router.get('/api/admin/productos/<id>/movimientos', (Request req, String id) async {
      try {
        final db = await _getDb();
        final pId = int.tryParse(id) ?? 0;
        final sql = '''
          SELECT ms.*,
                 COALESCE(p.nombre, 'Producto eliminado') AS nombre_producto,
                 m.nombre AS nombre_mesero,
                 COALESCE(cj.nombre, tc.nombre) AS nombre_cajero,
                 COALESCE(a.nombre, ta.nombre, 'Venta POS') AS nombre_admin
          FROM movimiento_stock ms
          LEFT JOIN producto p ON ms.id_producto = p.id_producto
          LEFT JOIN administrador_evento a ON ms.id_admin = a.id_admin
          LEFT JOIN comanda c ON (ms.motivo LIKE 'Venta comanda #' || c.id_comanda OR ms.motivo LIKE 'Anulación%#' || c.id_comanda)
          LEFT JOIN mesero m ON c.id_mesero = m.id_mesero
          LEFT JOIN cajero cj ON c.id_cajero = cj.id_cajero
          LEFT JOIN traspaso t ON (ms.motivo LIKE 'Traspaso #' || t.id_traspaso || '%' OR ms.motivo LIKE 'Compra #' || t.id_traspaso || '%')
          LEFT JOIN cajero tc ON t.id_cajero = tc.id_cajero
          LEFT JOIN administrador_evento ta ON t.id_admin = ta.id_admin
          WHERE ms.id_producto = ?
          ORDER BY ms.id_movimiento DESC
          LIMIT 60
        ''';
        final movs = await db.rawQuery(sql, [pId]);
        return _json({'success': true, 'movimientos': movs});
      } catch (e) {
        return _error('Error consultando movimientos: $e', statusCode: 500);
      }
    });

    // 32. ADMINISTRADORES / ENCARGADOS
    router.post('/api/admin/encargados', (Request req) async {
      try {
        final body = await _readJson(req);
        final nombre = (body['nombre'] ?? '').toString().trim();
        final usuario = (body['usuario'] ?? '').toString().trim();
        final password = (body['password'] ?? 'admin*12345').toString().trim();
        final rol = (body['rol'] ?? 'ADMINISTRADOR').toString();

        if (nombre.isEmpty || usuario.isEmpty) {
          return _error('Nombre y usuario requeridos', statusCode: 400);
        }

        final db = await _getDb();
        final id = await _writeMutex.run(() async {
          return await db.rawInsert('''
            INSERT INTO administrador_evento (id_evento, nombre, usuario, password, rol, activo)
            VALUES (1, ?, ?, ?, ?, 1)
          ''', [nombre, usuario, password, rol]);
        });

        return _json({'success': true, 'id_admin': id, 'message': 'Encargado registrado'});
      } catch (e) {
        return _error('Error al crear encargado: $e', statusCode: 500);
      }
    });

    router.put('/api/admin/encargados/<id>', (Request req, String id) async {
      try {
        final aId = int.tryParse(id) ?? 0;
        final body = await _readJson(req);
        final nombre = body['nombre'];
        final usuario = body['usuario'];
        final password = body['password'];
        final activo = body['activo'] != null ? ((body['activo'] == true || body['activo'] == 1) ? 1 : 0) : null;

        final db = await _getDb();
        await _writeMutex.run(() async {
          await db.rawUpdate('''
            UPDATE administrador_evento SET
              nombre = COALESCE(?, nombre),
              usuario = COALESCE(?, usuario),
              password = COALESCE(?, password),
              activo = COALESCE(?, activo)
            WHERE id_admin = ?
          ''', [nombre, usuario, password, activo, aId]);
        });

        return _json({'success': true, 'message': 'Encargado actualizado'});
      } catch (e) {
        return _error('Error al actualizar encargado: $e', statusCode: 500);
      }
    });

    router.delete('/api/admin/encargados/<id>', (Request req, String id) async {
      try {
        final db = await _getDb();
        final aId = int.tryParse(id) ?? 0;
        await _writeMutex.run(() async {
          await db.rawUpdate('UPDATE administrador_evento SET activo = 0 WHERE id_admin = ?', [aId]);
        });
        return _json({'success': true, 'message': 'Encargado desactivado'});
      } catch (e) {
        return _error('Error al desactivar encargado: $e', statusCode: 500);
      }
    });

    // 33. TRASPASOS DE STOCK
    router.post('/api/traspaso', (Request req) async {
      try {
        final body = await _readJson(req);
        final tipo = (body['tipo'] ?? '').toString().toUpperCase();
        final motivo = (body['motivo'] ?? '').toString().toUpperCase();
        final contraparte = (body['contraparte'] ?? '').toString().trim();
        final observaciones = (body['observaciones'] ?? '').toString().trim();
        final rawItems = body['items'] as List? ?? [];
        final idAdmin = body['id_admin'];
        final idCajero = body['id_cajero'];

        if (tipo != 'ENTRADA' && tipo != 'SALIDA') {
          return _json({'success': false, 'message': 'Tipo de movimiento no válido.'}, statusCode: 400);
        }
        if (contraparte.isEmpty) {
          return _json({'success': false, 'message': tipo == 'SALIDA' ? 'Falta decir a dónde va.' : 'Falta decir de dónde viene.'}, statusCode: 400);
        }
        if (rawItems.isEmpty) {
          return _json({'success': false, 'message': 'No hay ningún producto en el movimiento.'}, statusCode: 400);
        }

        final db = await _getDb();
        final now = DatabaseHelper.nowSql();

        final result = await _writeMutex.run(() async {
          return await db.transaction((txn) async {
            final idTraspaso = await txn.rawInsert('''
              INSERT INTO traspaso (tipo, motivo, contraparte, observaciones, id_cajero, id_admin, fecha_hora)
              VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', [tipo, motivo, contraparte, observaciones, idCajero, idAdmin, now]);

            final List<Map<String, dynamic>> lineas = [];
            for (var item in rawItems) {
              if (item is! Map) continue;
              final idProd = int.tryParse(item['id_producto']?.toString() ?? '0') ?? 0;
              final qty = int.tryParse(item['cantidad']?.toString() ?? '0') ?? 0;
              if (idProd <= 0 || qty <= 0) continue;

              final prodRows = await txn.rawQuery('SELECT nombre, stock_actual FROM producto WHERE id_producto = ? AND activo = 1', [idProd]);
              if (prodRows.isEmpty) throw Exception('El producto #$idProd ya no está disponible.');
              final prodName = prodRows.first['nombre'] as String;
              final currentStock = (prodRows.first['stock_actual'] as num).toInt();

              if (tipo == 'SALIDA') {
                if (currentStock < qty) {
                  throw Exception('No hay $qty de $prodName para mover (quedan $currentStock).');
                }
                await txn.rawUpdate('UPDATE producto SET stock_actual = stock_actual - ? WHERE id_producto = ?', [qty, idProd]);
              } else {
                await txn.rawUpdate('UPDATE producto SET stock_actual = stock_actual + ? WHERE id_producto = ?', [qty, idProd]);
              }

              await txn.rawInsert('INSERT INTO traspaso_detalle (id_traspaso, id_producto, cantidad) VALUES (?, ?, ?)', [idTraspaso, idProd, qty]);

              final afterStock = tipo == 'SALIDA' ? currentStock - qty : currentStock + qty;
              final texto = tipo == 'SALIDA'
                  ? 'Traspaso #$idTraspaso a $contraparte'
                  : (motivo == 'COMPRA' ? 'Compra #$idTraspaso a $contraparte' : 'Traspaso #$idTraspaso recibido de $contraparte');

              await txn.rawInsert('''
                INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo, fecha_hora)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              ''', [idProd, idAdmin, tipo, qty, currentStock, afterStock, texto, now]);

              lineas.add({
                'id_producto': idProd,
                'nombre': prodName,
                'cantidad': qty,
                'stock_despues': afterStock,
              });
            }
            return {'idTraspaso': idTraspaso, 'lineas': lineas};
          });
        });

        L1Cache.invalidateStock();

        return _json({
          'success': true,
          'id_traspaso': result['idTraspaso'],
          'tipo': tipo,
          'motivo': motivo,
          'contraparte': contraparte,
          'observaciones': observaciones,
          'items': result['lineas'],
          'message': tipo == 'SALIDA'
              ? 'Traspaso #${result['idTraspaso']} a $contraparte registrado.'
              : (motivo == 'COMPRA'
                  ? 'Compra #${result['idTraspaso']} registrada: el stock ya está actualizado.'
                  : 'Traspaso #${result['idTraspaso']} recibido de $contraparte.'),
        });
      } catch (e) {
        return _error('Error al registrar traspaso: ${e.toString().replaceAll("Exception: ", "")}', statusCode: 400);
      }
    });

    router.get('/api/traspasos', (Request req) async {
      try {
        final db = await _getDb();
        final traspasos = await db.rawQuery('''
          SELECT t.id_traspaso, t.tipo, t.motivo, t.contraparte, t.observaciones, t.fecha_hora,
                 c.nombre AS cajero,
                 (SELECT COUNT(*) FROM traspaso_detalle d WHERE d.id_traspaso = t.id_traspaso) AS lineas,
                 (SELECT COALESCE(SUM(d.cantidad), 0) FROM traspaso_detalle d WHERE d.id_traspaso = t.id_traspaso) AS unidades
            FROM traspaso t
            LEFT JOIN cajero c ON c.id_cajero = t.id_cajero
           ORDER BY t.id_traspaso DESC LIMIT 60
        ''');

        final destinos = await db.rawQuery('''
          SELECT contraparte, tipo, MAX(id_traspaso) AS ultimo
            FROM traspaso WHERE contraparte <> ''
           GROUP BY contraparte, tipo ORDER BY ultimo DESC LIMIT 20
        ''');

        return _json({'traspasos': traspasos, 'destinos': destinos});
      } catch (e) {
        return _error('Error listando traspasos: $e', statusCode: 500);
      }
    });

    router.get('/api/traspaso/<id>', (Request req, String id) async {
      try {
        final tId = int.tryParse(id) ?? 0;
        final db = await _getDb();
        final tRows = await db.rawQuery('''
          SELECT t.*, c.nombre AS cajero FROM traspaso t
            LEFT JOIN cajero c ON c.id_cajero = t.id_cajero
           WHERE t.id_traspaso = ?
        ''', [tId]);
        if (tRows.isEmpty) return _error('Traspaso no encontrado', statusCode: 404);

        final items = await db.rawQuery('''
          SELECT d.id_producto, d.cantidad, COALESCE(p.nombre, 'Producto eliminado') AS nombre
            FROM traspaso_detalle d
            LEFT JOIN producto p ON p.id_producto = d.id_producto
           WHERE d.id_traspaso = ?
        ''', [tId]);

        return _json({'success': true, 'traspaso': tRows.first, 'items': items});
      } catch (e) {
        return _error('Error consultando traspaso: $e', statusCode: 500);
      }
    });

    // 34. REPORTES Y AUDITORÍA
    router.get('/api/admin/reporte', (Request req) async {
      try {
        final db = await _getDb();
        final desde = req.url.queryParameters['desde'] ?? '2000-01-01 00:00:00';
        final hasta = req.url.queryParameters['hasta'] ?? '2099-12-31 23:59:59';
        final P = [desde, hasta];

        final resumen = await db.rawQuery('''
          SELECT
            COUNT(*) AS comandas,
            COALESCE(SUM(CASE WHEN estado_pago != 'ANULADO' AND COALESCE(es_cortesia, 0) = 0 THEN total END), 0) AS recaudado,
            SUM(CASE WHEN estado_pago != 'ANULADO' AND COALESCE(es_cortesia, 0) = 0 THEN 1 ELSE 0 END) AS validas,
            SUM(CASE WHEN estado_pago = 'ANULADO' THEN 1 ELSE 0 END) AS anuladas,
            COALESCE(SUM(CASE WHEN estado_pago = 'ANULADO' THEN total END), 0) AS importe_anulado,
            SUM(CASE WHEN COALESCE(es_cortesia, 0) = 1 THEN 1 ELSE 0 END) AS cortesias,
            COALESCE(SUM(CASE WHEN COALESCE(es_cortesia, 0) = 1 AND estado_pago != 'ANULADO' THEN total END), 0) AS importe_cortesia,
            SUM(CASE WHEN COALESCE(es_cortesia, 0) = 1 AND estado_pago != 'ANULADO' THEN 1 ELSE 0 END) AS cortesias_completadas,
            SUM(CASE WHEN COALESCE(es_cortesia, 0) = 1 AND estado_pago = 'ANULADO' THEN 1 ELSE 0 END) AS cortesias_anuladas,
            COALESCE(SUM(CASE WHEN COALESCE(es_cortesia, 0) = 1 AND estado_pago = 'ANULADO' THEN total END), 0) AS importe_cortesia_anulado
          FROM comanda WHERE fecha_hora BETWEEN ? AND ?
        ''', P);

        final unidades = await db.rawQuery('''
          SELECT COALESCE(SUM(d.cantidad), 0) AS n
          FROM detalle_comanda d JOIN comanda c ON c.id_comanda = d.id_comanda
          WHERE c.estado_pago != 'ANULADO' AND c.fecha_hora BETWEEN ? AND ?
        ''', P);

        final porMetodo = await db.rawQuery('''
          SELECT mp.nombre AS metodo,
                 COUNT(p.id_pago) AS pagos,
                 COALESCE(SUM(p.monto), 0) AS importe
          FROM pago_comanda p
          JOIN comanda c ON c.id_comanda = p.id_comanda
          JOIN metodo_pago mp ON mp.id_metodo_pago = p.id_metodo_pago
          WHERE p.estado = 'APROBADO' AND c.estado_pago != 'ANULADO' AND COALESCE(c.es_cortesia, 0) = 0
            AND c.fecha_hora BETWEEN ? AND ?
          GROUP BY mp.id_metodo_pago ORDER BY importe DESC
        ''', P);

        final porBarra = await db.rawQuery('''
          SELECT b.nombre_barra AS barra,
                 COUNT(CASE WHEN c.estado_pago != 'ANULADO' AND COALESCE(c.es_cortesia, 0) = 0 THEN 1 END) AS comandas,
                 COALESCE(SUM(CASE WHEN c.estado_pago != 'ANULADO' AND COALESCE(c.es_cortesia, 0) = 0 THEN c.total END), 0) AS importe
          FROM comanda c
          JOIN barra b ON b.id_barra = c.id_barra
          WHERE c.fecha_hora BETWEEN ? AND ?
          GROUP BY b.id_barra ORDER BY importe DESC
        ''', P);

        final porCajero = await db.rawQuery('''
          SELECT cj.nombre AS cajero,
                 COUNT(CASE WHEN c.estado_pago != 'ANULADO' AND COALESCE(c.es_cortesia, 0) = 0 THEN 1 END) AS comandas,
                 COALESCE(SUM(CASE WHEN c.estado_pago != 'ANULADO' AND COALESCE(c.es_cortesia, 0) = 0 THEN c.total END), 0) AS importe
          FROM comanda c
          JOIN cajero cj ON cj.id_cajero = c.id_cajero
          WHERE c.fecha_hora BETWEEN ? AND ?
          GROUP BY cj.id_cajero ORDER BY importe DESC
        ''', P);

        return _json({
          'resumen': resumen.isNotEmpty ? resumen.first : {},
          'unidades': (unidades.isNotEmpty ? unidades.first['n'] as num? : 0)?.toInt() ?? 0,
          'porMetodo': porMetodo,
          'porBarra': porBarra,
          'porCajero': porCajero,
        });
      } catch (e) {
        return _error('Error generando reporte: $e', statusCode: 500);
      }
    });

    // 34b. GET /api/admin/reporte.pdf
    router.get('/api/admin/reporte.pdf', (Request req) async {
      try {
        final db = await _getDb();
        final configRow = await db.rawQuery('SELECT * FROM configuracion WHERE id_configuracion = 1');
        final totalesRow = await db.rawQuery("SELECT COUNT(*) AS total_comandas, COALESCE(SUM(total), 0) AS total_ventas FROM comanda WHERE estatus != 'ANULADA'");

        final doc = pw.Document();
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MASTERDRINKS POS - REPORTE OFICIAL DE CIERRE', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800)),
                  pw.SizedBox(height: 8),
                  pw.Text('Evento: ${configRow.isNotEmpty ? configRow.first['evento'] : "Festival 2026"}'),
                  pw.Text('Barra: ${configRow.isNotEmpty ? configRow.first['barra'] : "Barra 1"}'),
                  pw.Text('Fecha de emisión: ${DateTime.now().toLocal()}'),
                  pw.Divider(thickness: 2),
                  pw.SizedBox(height: 12),
                  pw.Text('Total Comandas: ${totalesRow.isNotEmpty ? totalesRow.first['total_comandas'] : 0}', style: const pw.TextStyle(fontSize: 14)),
                  pw.Text('Total Recaudado: Bs. ${totalesRow.isNotEmpty ? totalesRow.first['total_ventas'] : 0.0}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ],
              );
            },
          ),
        );
        final bytes = await doc.save();
        return Response.ok(bytes, headers: {
          'Content-Type': 'application/pdf',
          'Content-Disposition': 'attachment; filename="reporte_cierre.pdf"',
        });
      } catch (e) {
        return _error('Error al generar PDF de reporte: $e', statusCode: 500);
      }
    });

    // 34c. GET /api/admin/comandas.pdf
    router.get('/api/admin/comandas.pdf', (Request req) async {
      try {
        final db = await _getDb();
        final comandas = await db.rawQuery('SELECT id_comanda, fecha_hora, total, estatus FROM comanda ORDER BY id_comanda DESC LIMIT 100');

        final doc = pw.Document();
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return [
                pw.Text('MASTERDRINKS POS - LISTADO DE COMANDAS', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.amber800)),
                pw.SizedBox(height: 8),
                pw.Text('Total comandas listadas: ${comandas.length}'),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 12),
                pw.TableHelper.fromTextArray(
                  headers: ['# Comanda', 'Fecha / Hora', 'Total (Bs.)', 'Estatus'],
                  data: comandas.map((c) => [
                    c['id_comanda'].toString(),
                    c['fecha_hora'].toString(),
                    c['total'].toString(),
                    c['estatus'].toString(),
                  ]).toList(),
                ),
              ];
            },
          ),
        );
        final bytes = await doc.save();
        return Response.ok(bytes, headers: {
          'Content-Type': 'application/pdf',
          'Content-Disposition': 'attachment; filename="comandas.pdf"',
        });
      } catch (e) {
        return _error('Error al generar PDF de comandas: $e', statusCode: 500);
      }
    });

    // 35. AUDITORÍA
    router.get('/api/admin/auditoria', (Request req) async {
      try {
        final db = await _getDb();
        final audits = await db.rawQuery('''
          SELECT au.*, COALESCE(a.nombre, 'Sistema') AS nombre_admin
          FROM auditoria_admin au
          LEFT JOIN administrador_evento a ON au.id_admin = a.id_admin
          ORDER BY au.id_auditoria DESC
        ''');

        final movs = await db.rawQuery('''
          SELECT ms.*,
                 COALESCE(p.nombre, 'Producto eliminado') AS nombre_producto,
                 m.nombre AS nombre_mesero,
                 COALESCE(cj.nombre, tc.nombre) AS nombre_cajero,
                 COALESCE(a.nombre, ta.nombre, 'Venta POS') AS nombre_admin
          FROM movimiento_stock ms
          LEFT JOIN producto p ON ms.id_producto = p.id_producto
          LEFT JOIN administrador_evento a ON ms.id_admin = a.id_admin
          LEFT JOIN comanda c ON (ms.motivo LIKE 'Venta comanda #' || c.id_comanda OR ms.motivo LIKE 'Anulación%#' || c.id_comanda)
          LEFT JOIN mesero m ON c.id_mesero = m.id_mesero
          LEFT JOIN cajero cj ON c.id_cajero = cj.id_cajero
          LEFT JOIN traspaso t ON (ms.motivo LIKE 'Traspaso #' || t.id_traspaso || '%' OR ms.motivo LIKE 'Compra #' || t.id_traspaso || '%')
          LEFT JOIN cajero tc ON t.id_cajero = tc.id_cajero
          LEFT JOIN administrador_evento ta ON t.id_admin = ta.id_admin
          ORDER BY ms.id_movimiento DESC
          LIMIT 500
        ''');
        final barras = await db.rawQuery('SELECT * FROM barra');
        final cajeros = await db.rawQuery('SELECT * FROM cajero');
        final metodos = await db.rawQuery('SELECT * FROM metodo_pago');

        return _json({
          'auditoria': audits,
          'movimientos': movs,
          'barras': barras,
          'cajeros': cajeros,
          'metodos_pago': metodos,
        });
      } catch (e) {
        return _error('Error consultando auditoría: $e', statusCode: 500);
      }
    });

    // 36. REIMPRESIONES
    router.get('/api/admin/reimpresiones', (Request req) async {
      try {
        final db = await _getDb();
        final desde = req.url.queryParameters['desde'];
        final hasta = req.url.queryParameters['hasta'];
        final String rango = (desde != null && hasta != null && desde.isNotEmpty && hasta.isNotEmpty)
            ? 'AND i.fecha_hora_impresion BETWEEN ? AND ?'
            : '';
        final List<dynamic> args = (desde != null && hasta != null && desde.isNotEmpty && hasta.isNotEmpty)
            ? [desde, hasta]
            : [];

        final sql = '''
          SELECT i.id_comanda AS id_comanda, i.numero_copia - 1 AS numero_reimpresion,
                 i.fecha_hora_impresion AS fecha,
                 COALESCE(caj.nombre, 'sin registrar') AS cajero,
                 COALESCE(mes.nombre, 'sin registrar') AS mesero,
                 COALESCE(c.total, 0) AS total
          FROM impresion_comanda_cajero i
          LEFT JOIN comanda c ON c.id_comanda = i.id_comanda
          LEFT JOIN cajero  caj ON caj.id_cajero = i.id_cajero
          LEFT JOIN mesero  mes ON mes.id_mesero = i.id_mesero
          WHERE i.numero_copia > 1 $rango
          ORDER BY fecha DESC, id_comanda DESC
        ''';
        final reimpresiones = await db.rawQuery(sql, args);
        return _json({'success': true, 'reimpresiones': reimpresiones});
      } catch (e) {
        return _error('Error listando reimpresiones: $e', statusCode: 500);
      }
    });

    return router;
  }
}
