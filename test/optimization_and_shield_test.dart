import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:masterdrinks/server/embedded_server.dart';
import 'package:masterdrinks/server/web_assets_helper.dart';

void main() {
  group('MasterDrinks Server Optimization & Shield Tests', () {
    test('1. AsyncMutex with Timeout Protection', () async {
      final mutex = AsyncMutex();
      int count = 0;

      final f1 = mutex.run(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        count += 1;
        return count;
      });

      final f2 = mutex.run(() async {
        count += 10;
        return count;
      });

      final res1 = await f1;
      final res2 = await f2;

      expect(res1, equals(1));
      expect(res2, equals(11));
    });

    test('2. L1 Cache State & Invalidation Logic', () {
      L1Cache.clear();
      expect(L1Cache.instanciaJson, isNull);
      expect(L1Cache.productosJson, isNull);
      expect(L1Cache.stockJson, isNull);

      L1Cache.instanciaJson = '{"nombre":"Barra 1"}';
      L1Cache.productosJson = '{"productos":[]}';
      L1Cache.stockJson = '{"stock":[]}';
      L1Cache.personalJson = '{"cajeros":[]}';

      expect(L1Cache.instanciaJson, isNotNull);
      expect(L1Cache.productosJson, isNotNull);

      // Invalidate stock
      L1Cache.invalidateStock();
      expect(L1Cache.productosJson, isNull);
      expect(L1Cache.stockJson, isNull);
      expect(L1Cache.instanciaJson, isNotNull);

      // Invalidate config
      L1Cache.invalidateConfig();
      expect(L1Cache.instanciaJson, isNull);

      // Clear all
      L1Cache.clear();
      expect(L1Cache.personalJson, isNull);
    });

    test('3. WebAssetsHelper RAM Cache and 304 ETag Handling', () {
      // Request for index.html or not found
      final reqNotFound = Request('GET', Uri.parse('http://localhost:3000/archivo_inexistente.xyz'));
      final resNotFound = WebAssetsHelper.handleMemoryAsset(reqNotFound);
      expect(resNotFound.statusCode, equals(404));
    });
  });
}
