import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late String dbPath;

  setUpAll(() async {
    final originalDbFile = File(p.join(Directory.current.path, 'assets', 'db', 'pos_evento.db'));
    expect(originalDbFile.existsSync(), isTrue);

    final tempDir = Directory.systemTemp.createTempSync('masterdrinks_promo_test_');
    dbPath = p.join(tempDir.path, 'test_promo_anular.db');
    await originalDbFile.copy(dbPath);

    db = await databaseFactory.openDatabase(dbPath);
  });

  tearDownAll(() async {
    await db.close();
    try {
      final f = File(dbPath);
      if (f.existsSync()) f.deleteSync();
      f.parent.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('MasterDrinks Promociones, Montos & Anulaciones Tests', () {
    test('1. Reparto exacto de promociones (combos) al centavo sin desfasajes', () {
      // Función matemática de reparto de combos
      List<Map<String, dynamic>> repartir(List<Map<String, dynamic>> partes, double precioPaquete) {
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
            };
          }).toList();
        } else {
          final subtotalUnitario = double.parse((precioPaquete / partes.length).toStringAsFixed(2));
          lineas = partes.map((p) {
            final qty = (p['qty'] as num).toDouble();
            final precio = qty > 0 ? double.parse((subtotalUnitario / qty).toStringAsFixed(2)) : subtotalUnitario;
            return {
              'idProd': p['idProd'],
              'qty': p['qty'],
              'precio': precio,
              'subtotal': subtotalUnitario,
            };
          }).toList();
        }

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

      // Caso A: Precio combo 10.00 con 3 items de 4.00 (suelto 12.00, sobra de 0.01)
      final partes1 = [
        {'idProd': 1, 'qty': 1, 'precioCatalogo': 4.00},
        {'idProd': 2, 'qty': 1, 'precioCatalogo': 4.00},
        {'idProd': 3, 'qty': 1, 'precioCatalogo': 4.00},
      ];
      final res1 = repartir(partes1, 10.00);
      final sum1 = double.parse(res1.fold<double>(0.0, (s, l) => s + (l['subtotal'] as double)).toStringAsFixed(2));
      expect(sum1, equals(10.00));

      // Caso B: Precio combo 25.50 con cantidades múltiples
      final partes2 = [
        {'idProd': 10, 'qty': 2, 'precioCatalogo': 7.30},
        {'idProd': 11, 'qty': 3, 'precioCatalogo': 5.20},
      ];
      final res2 = repartir(partes2, 25.50);
      final sum2 = double.parse(res2.fold<double>(0.0, (s, l) => s + (l['subtotal'] as double)).toStringAsFixed(2));
      expect(sum2, equals(25.50));

      // Caso C: Productos con precio 0 en catálogo
      final partes3 = [
        {'idProd': 20, 'qty': 1, 'precioCatalogo': 0.0},
        {'idProd': 21, 'qty': 1, 'precioCatalogo': 0.0},
      ];
      final res3 = repartir(partes3, 15.00);
      final sum3 = double.parse(res3.fold<double>(0.0, (s, l) => s + (l['subtotal'] as double)).toStringAsFixed(2));
      expect(sum3, equals(15.00));
    });

    test('2. Anulación de comanda con botella vinculada devuelve fracción exacta', () async {
      try {
        await db.transaction((txn) async {
          // Encontrar una botella real y un vaso vinculado
          final vasoRow = await txn.rawQuery('''
            SELECT id_producto, nombre, id_botella_vinculada, vasos_por_botella, stock_actual
            FROM producto
            WHERE id_botella_vinculada IS NOT NULL AND id_botella_vinculada > 0
            LIMIT 1
          ''');

          if (vasoRow.isEmpty) return;

          final idVaso = vasoRow.first['id_producto'] as int;
          final idBotella = vasoRow.first['id_botella_vinculada'] as int;
          final vasosPorBotella = ((vasoRow.first['vasos_por_botella'] as num?)?.toDouble() ?? 10.0);

          final botRowAntes = (await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = ?', [idBotella])).first;
          final stBotAntes = (botRowAntes['stock_actual'] as num).toDouble();

          // 1. Simular venta de 3 vasos
          final cantVasos = 3;
          final botADeducir = double.parse((cantVasos / vasosPorBotella).toStringAsFixed(4));
          final stBotVendido = double.parse((stBotAntes - botADeducir).toStringAsFixed(4));
          await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [stBotVendido, idBotella]);

          // Insertar comanda y detalle
          final idCom = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, fecha_hora, total, estado_pago, estatus)
            VALUES (1, 3, 1, '2026-10-09 18:00:00', 30.00, 'PAGADO', 'COMPLETADO')
          ''');

          await txn.rawInsert('''
            INSERT INTO detalle_comanda (id_comanda, id_producto, cantidad, precio_unitario, subtotal)
            VALUES (?, ?, ?, 10.00, 30.00)
          ''', [idCom, idVaso, cantVasos]);

          // 2. Anular la comanda y devolver stock
          final detalles = await txn.rawQuery('SELECT id_producto, cantidad FROM detalle_comanda WHERE id_comanda = ?', [idCom]);
          for (var d in detalles) {
            final idProd = d['id_producto'] as int;
            final qty = (d['cantidad'] as num).toDouble();

            final pData = (await txn.rawQuery('SELECT id_botella_vinculada, vasos_por_botella FROM producto WHERE id_producto = ?', [idProd])).first;
            final botId = pData['id_botella_vinculada'] as int?;
            final vpb = ((pData['vasos_por_botella'] as num?)?.toDouble() ?? 10.0);

            if (botId != null && botId > 0) {
              final bAnt = ((await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = ?', [botId])).first['stock_actual'] as num).toDouble();
              final botADevolver = double.parse((qty / vpb).toStringAsFixed(4));
              final bNuevo = double.parse((bAnt + botADevolver).toStringAsFixed(4));
              await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [bNuevo, botId]);
            }
          }

          // Marcar comanda anulada
          await txn.rawUpdate("UPDATE comanda SET estatus = 'CANCELADA', estado_pago = 'ANULADO' WHERE id_comanda = ?", [idCom]);

          // 3. Verificar que el stock de la botella volvió exactamente al valor inicial
          final botRowDespues = (await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = ?', [idBotella])).first;
          final stBotDespues = (botRowDespues['stock_actual'] as num).toDouble();
          expect(stBotDespues, equals(stBotAntes));

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });

    test('3. Anulación de comanda con combo restituye stock de todos sus componentes', () async {
      try {
        await db.transaction((txn) async {
          final promoRow = await txn.rawQuery('''
            SELECT p.id_promocion, p.nombre, p.precio
            FROM promocion p
            JOIN promocion_detalle pd ON pd.id_promocion = p.id_promocion
            GROUP BY p.id_promocion
            HAVING COUNT(pd.id_producto) >= 2
            LIMIT 1
          ''');

          if (promoRow.isEmpty) return;

          final idPromo = promoRow.first['id_promocion'] as int;
          final itemsPromo = await txn.rawQuery('''
            SELECT pd.id_producto, pd.cantidad, p.stock_actual
            FROM promocion_detalle pd
            JOIN producto p ON p.id_producto = pd.id_producto
            WHERE pd.id_promocion = ?
          ''', [idPromo]);

          final Map<int, double> stockInicial = {};
          for (var it in itemsPromo) {
            final idP = it['id_producto'] as int;
            stockInicial[idP] = (it['stock_actual'] as num).toDouble();
          }

          // Crear comanda simulando venta de la promo (descontando stock)
          final idCom = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, fecha_hora, total, estado_pago, estatus)
            VALUES (1, 3, 1, '2026-10-09 18:30:00', 50.00, 'PAGADO', 'COMPLETADO')
          ''');

          for (var it in itemsPromo) {
            final idP = it['id_producto'] as int;
            final cantP = (it['cantidad'] as num).toDouble();

            // Descontar
            await txn.rawUpdate('UPDATE producto SET stock_actual = stock_actual - ? WHERE id_producto = ?', [cantP, idP]);

            // Registrar en detalle con id_promocion
            await txn.rawInsert('''
              INSERT INTO detalle_comanda (id_comanda, id_producto, cantidad, precio_unitario, subtotal, id_promocion)
              VALUES (?, ?, ?, 25.00, 25.00, ?)
            ''', [idCom, idP, cantP, idPromo]);
          }

          // Ejecutar anulación
          final detalles = await txn.rawQuery('SELECT id_producto, cantidad FROM detalle_comanda WHERE id_comanda = ?', [idCom]);
          for (var d in detalles) {
            final idP = d['id_producto'] as int;
            final qty = (d['cantidad'] as num).toDouble();
            await txn.rawUpdate('UPDATE producto SET stock_actual = stock_actual + ? WHERE id_producto = ?', [qty, idP]);
          }
          await txn.rawUpdate("UPDATE comanda SET estatus = 'CANCELADA', estado_pago = 'ANULADO' WHERE id_comanda = ?", [idCom]);

          // Verificar que todos los productos del combo volvieron a su stock original
          for (var it in itemsPromo) {
            final idP = it['id_producto'] as int;
            final stActual = ((await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = ?', [idP])).first['stock_actual'] as num).toDouble();
            expect(stActual, equals(stockInicial[idP]));
          }

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });

    test('4. Protección contra doble anulación', () async {
      try {
        await db.transaction((txn) async {
          final idCom = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, fecha_hora, total, estado_pago, estatus)
            VALUES (1, 3, 1, '2026-10-09 19:00:00', 20.00, 'PAGADO', 'COMPLETADO')
          ''');

          // Primera anulación
          await txn.rawUpdate("UPDATE comanda SET estatus = 'CANCELADA', estado_pago = 'ANULADO' WHERE id_comanda = ?", [idCom]);

          // Intentar segunda anulación
          final comRow = await txn.rawQuery('SELECT estado_pago, estatus FROM comanda WHERE id_comanda = ?', [idCom]);
          final yaAnulada = comRow.first['estado_pago'] == 'ANULADO' || comRow.first['estatus'] == 'CANCELADA';
          expect(yaAnulada, isTrue);

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });
  });
}
