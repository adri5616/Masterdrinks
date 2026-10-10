import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'data/database/database_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar base de datos SQLite en desktop o móvil
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Precalentar base de datos en plataformas nativas
  if (!kIsWeb) {
    try {
      await DatabaseHelper.instance.database;
    } catch (e) {
      print('Error inicializando base de datos: $e');
    }
  }

  runApp(const MasterDrinksApp());
}
