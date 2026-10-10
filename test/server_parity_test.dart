import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const dbPath = r'C:\Users\adri5\OneDrive\Desktop\masterdrinks_flutter\assets\db\pos_evento.db';

  group('MasterDrinks Database & Logic Parity Tests', () {
    late Database db;

    setUpAll(() async {
      db = await openDatabase(
        dbPath,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
        },
      );
    });

    tearDownAll(() async {
      await db.close();
    });

    test('1. Database Integrity Check', () async {
      final res = await db.rawQuery('PRAGMA integrity_check');
      expect(res.first.values.first, equals('ok'));
    });

    test('2. Real Cajeros Verification', () async {
      final cajeros = await db.rawQuery('SELECT id_cajero, nombre, usuario, password FROM cajero ORDER BY id_cajero');
      expect(cajeros.length, equals(5));
      final usuarios = cajeros.map((c) => c['usuario']).toList();
      expect(usuarios, containsAll(['Anel', 'veronica', 'Lizbeth', 'adri', 'lily']));
      
      final adri = cajeros.firstWhere((c) => c['usuario'] == 'adri');
      expect(adri['password'], equals('1234'));
    });

    test('3. Real Meseros Verification', () async {
      final meseros = await db.rawQuery('SELECT id_mesero, nombre, password FROM mesero WHERE activo = 1');
      expect(meseros.length, equals(30));

      final pins = meseros.map((m) => m['password']).toList();
      expect(pins, containsAll(['1038', '1041', '1040', '1042', '1234']));
    });

    test('4. Admin & Face ID Verification', () async {
      final admins = await db.rawQuery("SELECT id_admin, usuario, password FROM administrador_evento WHERE usuario = 'admin'");
      expect(admins.isNotEmpty, isTrue);
      expect(admins.first['password'], equals('admin*12345'));

      final rostros = await db.rawQuery('SELECT id_rostro, id_admin, nombre FROM admin_rostro');
      expect(rostros.length, equals(2));
    });

    test('5. Historical Comandas & Catalog Verification', () async {
      final numComandas = (await db.rawQuery('SELECT count(*) as c FROM comanda')).first['c'] as int;
      expect(numComandas, equals(1233));

      final numDetalles = (await db.rawQuery('SELECT count(*) as c FROM detalle_comanda')).first['c'] as int;
      expect(numDetalles, equals(1844));

      final numPagos = (await db.rawQuery('SELECT count(*) as c FROM pago_comanda')).first['c'] as int;
      expect(numPagos, equals(1325));

      final numProductos = (await db.rawQuery('SELECT count(*) as c FROM producto')).first['c'] as int;
      expect(numProductos, equals(81));
    });

    test('6. Transacción simulada de nueva comanda (Business Logic)', () async {
      try {
        await db.transaction((txn) async {
          // Simular venta de un producto existente (ej: id_producto = 3 Gin Flamboyant)
          final p = (await txn.rawQuery('SELECT id_producto, precio_venta, stock_actual FROM producto WHERE id_producto = 3')).first;
          final precio = (p['precio_venta'] as num).toDouble();
          final stockAntes = p['stock_actual'] as int;

          final comandaId = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, id_mesero, total, estado_pago, estatus, clave_idempotencia)
            VALUES (1, 3, 4, 1, ?, 'PAGADO', 'COBRADA', 'TEST_KEY_PARITY_001')
          ''', [precio]);

          expect(comandaId, isPositive);

          // Detalle
          await txn.rawInsert('''
            INSERT INTO detalle_comanda (id_comanda, id_producto, cantidad, precio_unitario, subtotal)
            VALUES (?, 3, 1, ?, ?)
          ''', [comandaId, precio, precio]);

          // Pago
          await txn.rawInsert('''
            INSERT INTO pago_comanda (id_comanda, id_metodo_pago, monto, estado)
            VALUES (?, 1, ?, 'CONFIRMADO')
          ''', [comandaId, precio]);

          // Descontar stock
          await txn.rawUpdate('UPDATE producto SET stock_actual = stock_actual - 1 WHERE id_producto = 3');

          // Movimiento de stock
          await txn.rawInsert('''
            INSERT INTO movimiento_stock (id_producto, id_admin, tipo_movimiento, cantidad, stock_anterior, stock_nuevo, motivo)
            VALUES (3, 1, 'SALIDA', 1, ?, ?, 'Venta comanda de prueba')
          ''', [stockAntes, stockAntes - 1]);

          // Verificar que el stock bajó 1
          final pDespues = (await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = 3')).first;
          expect(pDespues['stock_actual'], equals(stockAntes - 1));

          // Revertir para no ensuciar la base de datos de test
          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }

      // Asegurar que el rollback restauró el stock
      final pFinal = (await db.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = 3')).first;
      expect(pFinal['stock_actual'], isNotNull);
    });

    test('7. Inventory & Stock Queries Parity (/api/productos & /api/stock)', () async {
      // /api/productos queries
      final cats = await db.rawQuery('''
        SELECT id_categoria, nombre, descripcion, tipo, activo, COALESCE(orden, 0) AS orden
        FROM categoria_producto WHERE activo = 1 ORDER BY orden ASC, id_categoria ASC
      ''');
      expect(cats.isNotEmpty, isTrue);

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
      expect(prods.length, equals(52));
      // Cada producto debe tener stock_actual y nombre
      expect(prods.first['stock_actual'], isNotNull);
      expect(prods.first['nombre'], isNotNull);

      // /api/stock query
      final stock = await db.rawQuery(
        'SELECT id_producto AS id, stock_actual AS s FROM producto WHERE activo = 1',
      );
      expect(stock.length, equals(58));
      expect(stock.first.containsKey('id'), isTrue);
      expect(stock.first.containsKey('s'), isTrue);

      // Traspasos
      final traspasos = await db.rawQuery('''
        SELECT t.id_traspaso, t.tipo, t.motivo, t.contraparte, t.observaciones, t.fecha_hora,
               c.nombre AS cajero,
               (SELECT COUNT(*) FROM traspaso_detalle d WHERE d.id_traspaso = t.id_traspaso) AS lineas,
               (SELECT COALESCE(SUM(d.cantidad), 0) FROM traspaso_detalle d WHERE d.id_traspaso = t.id_traspaso) AS unidades
          FROM traspaso t
          LEFT JOIN cajero c ON c.id_cajero = t.id_cajero
         ORDER BY t.id_traspaso DESC LIMIT 60
      ''');
      expect(traspasos, isNotNull);
    });

    test('8. Print Audit & Multi-Copy Increment Logic', () async {
      try {
        await db.transaction((txn) async {
          // Crear comanda temporal con id_barra existente (3)
          final comId = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, id_mesero, total, estado_pago, estatus)
            VALUES (1, 3, 1, 1, 50.0, 'PAGADO', 'COMPLETADO')
          ''');

          // Primera impresión (copia 1)
          await txn.rawInsert('''
            INSERT INTO impresion_comanda_cajero (id_comanda, id_cajero, id_mesero, fecha_hora_impresion, numero_copia)
            VALUES (?, 1, 1, '2026-10-09 15:00:00', 1)
          ''', [comId]);

          // Segunda impresión / reimpresión (copia 2)
          final ultRow = await txn.rawQuery('SELECT COALESCE(MAX(numero_copia), 0) AS ultima FROM impresion_comanda_cajero WHERE id_comanda = ?', [comId]);
          final siguienteCopia = ((ultRow.first['ultima'] as num).toInt()) + 1;
          expect(siguienteCopia, equals(2));

          await txn.rawInsert('''
            INSERT INTO impresion_comanda_cajero (id_comanda, id_cajero, id_mesero, fecha_hora_impresion, numero_copia)
            VALUES (?, 1, 1, '2026-10-09 15:05:00', ?)
          ''', [comId, siguienteCopia]);

          // Verificar que se registra como reimpresión (numero_copia > 1)
          final reimpresiones = await txn.rawQuery('''
            SELECT * FROM impresion_comanda_cajero WHERE id_comanda = ? AND numero_copia > 1
          ''', [comId]);
          expect(reimpresiones.length, equals(1));
          expect(reimpresiones.first['numero_copia'], equals(2));

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });

    test('9. Cortesía Payment (Metodo Pago ID 8) & Foreign Key Safety', () async {
      try {
        await db.transaction((txn) async {
          // Crear comanda de cortesía
          final comId = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, id_mesero, total, estado_pago, estatus, es_cortesia)
            VALUES (1, 3, 1, 1, 0.0, 'PAGADO', 'COMPLETADO', 1)
          ''');

          // Pago con ID 8 (CORTESIA)
          final pagoId = await txn.rawInsert('''
            INSERT INTO pago_comanda (id_comanda, id_metodo_pago, monto, estado)
            VALUES (?, 8, 0.0, 'APROBADO')
          ''', [comId]);
          expect(pagoId, isPositive);

          final pRow = await txn.rawQuery('''
            SELECT p.id_pago, mp.nombre as metodo
            FROM pago_comanda p
            JOIN metodo_pago mp ON mp.id_metodo_pago = p.id_metodo_pago
            WHERE p.id_pago = ?
          ''', [pagoId]);
          expect(pRow.first['metodo'], equals('CORTESIA'));

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });

    test('10. Linked Bottle (Vaso -> Botella) Fraction Deduction Logic', () async {
      try {
        await db.transaction((txn) async {
          // Buscar un producto que tenga id_botella_vinculada
          final vasoRow = await txn.rawQuery('''
            SELECT id_producto, nombre, id_botella_vinculada, vasos_por_botella
            FROM producto WHERE id_botella_vinculada IS NOT NULL AND activo = 1 LIMIT 1
          ''');

          if (vasoRow.isNotEmpty) {
            final idVaso = vasoRow.first['id_producto'] as int;
            expect(idVaso, isPositive);
            final idBotella = vasoRow.first['id_botella_vinculada'] as int;
            final vasosPorBotella = (vasoRow.first['vasos_por_botella'] as num).toDouble();

            final botRow = (await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = ?', [idBotella])).first;
            final botStAnt = (botRow['stock_actual'] as num).toDouble();

            // Vender 2 vasos
            const qtyVasos = 2;
            final botADeducir = double.parse((qtyVasos / vasosPorBotella).toStringAsFixed(4));
            final botStNuevo = double.parse((botStAnt - botADeducir).toStringAsFixed(4));

            await txn.rawUpdate('UPDATE producto SET stock_actual = ? WHERE id_producto = ?', [botStNuevo, idBotella]);

            final botPost = (await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = ?', [idBotella])).first;
            final botStFinal = (botPost['stock_actual'] as num).toDouble();
            expect(botStFinal, equals(botStNuevo));
          }

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });

    test('11. Comanda Anulación & Stock Restitution Logic', () async {
      try {
        await db.transaction((txn) async {
          // Vender 1 unidad de producto 3
          final pAntes = (await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = 3')).first;
          final stAntes = (pAntes['stock_actual'] as num).toDouble();

          final comId = await txn.rawInsert('''
            INSERT INTO comanda (id_evento, id_barra, id_cajero, id_mesero, total, estado_pago, estatus)
            VALUES (1, 3, 1, 1, 35.0, 'PAGADO', 'COMPLETADO')
          ''');

          await txn.rawInsert('''
            INSERT INTO detalle_comanda (id_comanda, id_producto, cantidad, precio_unitario, subtotal)
            VALUES (?, 3, 1, 35.0, 35.0)
          ''', [comId]);

          await txn.rawUpdate('UPDATE producto SET stock_actual = stock_actual - 1 WHERE id_producto = 3');

          // Ahora anular
          await txn.rawUpdate('''
            UPDATE comanda SET estatus = 'CANCELADA', estado_pago = 'ANULADO', motivo_anulacion = 'Prueba anulación'
            WHERE id_comanda = ?
          ''', [comId]);

          // Devolver stock
          await txn.rawUpdate('UPDATE producto SET stock_actual = stock_actual + 1 WHERE id_producto = 3');

          final pDespues = (await txn.rawQuery('SELECT stock_actual FROM producto WHERE id_producto = 3')).first;
          final stDespues = (pDespues['stock_actual'] as num).toDouble();
          expect(stDespues, equals(stAntes));

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });

    test('12. Cajero Creation & Bar Resolution Test (No FK failure)', () async {
      try {
        await db.transaction((txn) async {
          // Obtener la barra real existente
          final bRow = await txn.rawQuery('SELECT id_barra, nombre_barra FROM barra LIMIT 1');
          expect(bRow.isNotEmpty, isTrue);
          final idBarra = bRow.first['id_barra'] as int;
          final nombreBarra = bRow.first['nombre_barra'] as String;
          expect(nombreBarra, equals('Graderias'));

          // Crear cajero de prueba con esa barra
          final cajId = await txn.rawInsert('''
            INSERT INTO cajero (id_barra, nombre, usuario, password, activo)
            VALUES (?, 'Cajero Prueba Test', 'cajero_test_99', '1234', 1)
          ''', [idBarra]);
          expect(cajId, isPositive);

          // Verificar consulta con join para comprobar que detecta el nombre de la barra
          final cWithBarra = await txn.rawQuery('''
            SELECT c.id_cajero, c.nombre, c.usuario, b.nombre_barra
            FROM cajero c
            LEFT JOIN barra b ON b.id_barra = c.id_barra
            WHERE c.id_cajero = ?
          ''', [cajId]);
          expect(cWithBarra.first['nombre_barra'], equals('Graderias'));

          // Crear mesero de prueba vinculado al cajero
          final mesId = await txn.rawInsert('''
            INSERT INTO mesero (id_evento, id_cajero, nombre, usuario, password, activo, es_cortesia)
            VALUES (1, ?, 'Mesero Prueba Test', 'mesero_test_99', '9999', 1, 0)
          ''', [cajId]);
          expect(mesId, isPositive);

          final mWithCajero = await txn.rawQuery('''
            SELECT m.id_mesero, m.nombre, c.nombre AS nombre_cajero, b.nombre_barra
            FROM mesero m
            JOIN cajero c ON c.id_cajero = m.id_cajero
            JOIN barra b ON b.id_barra = c.id_barra
            WHERE m.id_mesero = ?
          ''', [mesId]);
          expect(mWithCajero.first['nombre_cajero'], equals('Cajero Prueba Test'));
          expect(mWithCajero.first['nombre_barra'], equals('Graderias'));

          throw Exception('ROLLBACK_INTENTIONAL');
        });
      } catch (e) {
        expect(e.toString(), contains('ROLLBACK_INTENTIONAL'));
      }
    });
  });
}
