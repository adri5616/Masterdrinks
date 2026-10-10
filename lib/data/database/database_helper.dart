import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pos_evento.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Inicializar FFI en Windows/Linux/macOS
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String dbPath;
    if (!kIsWeb && Platform.isWindows) {
      final docDir = await getApplicationDocumentsDirectory();
      final appDir = Directory(p.join(docDir.path, 'MasterDrinks'));
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      dbPath = p.join(appDir.path, filePath);
    } else {
      final databasesPath = await getDatabasesPath();
      dbPath = p.join(databasesPath, filePath);
    }

    // Asegurar que la base de datos real completa (12.4MB) de MasterDrinks2 esté cargada
    final file = File(dbPath);
    final marker = File('$dbPath.verified_v1');
    bool needsCopy = !await file.exists() || await file.length() < 12000000;
    if (!needsCopy && !await marker.exists()) {
      try {
        final tempDb = await openReadOnlyDatabase(dbPath);
        final checkAdmin = await tempDb.rawQuery("SELECT count(*) as c FROM administrador_evento WHERE usuario = 'admin'");
        final checkCajero = await tempDb.rawQuery("SELECT count(*) as c FROM cajero");
        await tempDb.close();
        final numAdmins = checkAdmin.isEmpty ? 0 : (checkAdmin.first['c'] as int? ?? 0);
        final numCajeros = checkCajero.isEmpty ? 0 : (checkCajero.first['c'] as int? ?? 0);
        if (numAdmins == 0 || numCajeros < 5) {
          needsCopy = true;
        } else {
          await marker.writeAsString('ok');
        }
      } catch (_) {
        needsCopy = true;
      }
    }

    if (needsCopy) {
      try {
        print('📦 Extrayendo base de datos original pos_evento.db (12.4MB)...');
        final data = await rootBundle.load('assets/db/pos_evento.db');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }
        await file.writeAsBytes(bytes, flush: true);
        await marker.writeAsString('ok');
        print('✅ Base de datos real extraída con éxito: ${bytes.length} bytes.');
      } catch (e) {
        print('⚠️ Error al extraer pos_evento.db desde assets: $e');
      }
    }

    return await openDatabase(
      dbPath,
      onConfigure: (db) async {
        // Performance-critical PRAGMAs for high-volume POS
        try { await db.execute('PRAGMA journal_mode = WAL'); } catch (_) {}
        try { await db.execute('PRAGMA synchronous = NORMAL'); } catch (_) {}
        try { await db.execute('PRAGMA busy_timeout = 30000'); } catch (_) {}
        try { await db.execute('PRAGMA cache_size = -64000'); } catch (_) {}  // 64MB cache en RAM
        try { await db.execute('PRAGMA temp_store = MEMORY'); } catch (_) {}
        try { await db.execute('PRAGMA mmap_size = 268435456'); } catch (_) {}  // 256MB mmap
        try { await db.execute('PRAGMA foreign_keys = ON'); } catch (_) {}
        try { await db.execute('PRAGMA page_size = 4096'); } catch (_) {}
      },
      onOpen: (db) async {
        // Garantizar que la tabla de Face ID (admin_rostro) siempre exista
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS admin_rostro (
              id_rostro INTEGER PRIMARY KEY AUTOINCREMENT,
              id_admin INTEGER,
              nombre TEXT,
              descriptor TEXT,
              foto_referencia TEXT,
              fecha_registro TEXT DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY(id_admin) REFERENCES administrador_evento(id_admin)
            )
          ''');
        } catch (_) {}

        // Columnas opcionales para configuracion
        try { await db.execute('ALTER TABLE configuracion ADD COLUMN logo_ticket TEXT'); } catch (_) {}

        // Columnas opcionales para productos
        try { await db.execute('ALTER TABLE producto ADD COLUMN orden INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE producto ADD COLUMN id_botella_vinculada INTEGER'); } catch (_) {}
        try { await db.execute('ALTER TABLE producto ADD COLUMN vasos_por_botella INTEGER DEFAULT 10'); } catch (_) {}
        try { await db.execute('ALTER TABLE categoria_producto ADD COLUMN orden INTEGER DEFAULT 0'); } catch (_) {}
        try { await db.execute('ALTER TABLE promocion ADD COLUMN foto TEXT'); } catch (_) {}
        try { await db.execute('ALTER TABLE promocion ADD COLUMN precio_combo REAL'); } catch (_) {}
        try { await db.execute('ALTER TABLE promocion ADD COLUMN eliminada INTEGER DEFAULT 0'); } catch (_) {}

        // Índices críticos para alto volumen de ventas y consultas concurrentes
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_cajero ON comanda(id_cajero)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_mesero ON comanda(id_mesero)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_estatus ON comanda(estatus)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_fecha ON comanda(fecha_hora)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_comanda ON detalle_comanda(id_comanda)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_producto ON detalle_comanda(id_producto)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_pago_comanda ON pago_comanda(id_comanda)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_movimiento_producto ON movimiento_stock(id_producto)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_producto_categoria ON producto(id_categoria)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_producto_activo ON producto(activo)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_cajero_usuario ON cajero(usuario)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_admin_usuario ON administrador_evento(usuario)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_mesero_password ON mesero(password)'); } catch (_) {}
        try { await db.execute('CREATE INDEX IF NOT EXISTS idx_rostro_admin ON admin_rostro(id_admin)'); } catch (_) {}
      },
    );
  }

  static String nowSql([DateTime? dt]) {
    final d = dt ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS evento (
        id_evento INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre_evento TEXT,
        fecha_evento TEXT,
        lugar TEXT,
        descripcion TEXT,
        hora_inicio TEXT,
        hora_fin TEXT,
        activo INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS barra (
        id_barra INTEGER PRIMARY KEY AUTOINCREMENT,
        id_evento INTEGER,
        nombre_barra TEXT,
        descripcion TEXT,
        ubicacion TEXT,
        activo INTEGER DEFAULT 1,
        FOREIGN KEY(id_evento) REFERENCES evento(id_evento)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cajero (
        id_cajero INTEGER PRIMARY KEY AUTOINCREMENT,
        id_barra INTEGER,
        nombre TEXT,
        usuario TEXT UNIQUE,
        password TEXT,
        activo INTEGER DEFAULT 1,
        FOREIGN KEY(id_barra) REFERENCES barra(id_barra)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS administrador_evento (
        id_admin INTEGER PRIMARY KEY AUTOINCREMENT,
        id_evento INTEGER,
        nombre TEXT,
        usuario TEXT UNIQUE,
        password TEXT,
        rol TEXT,
        activo INTEGER DEFAULT 1,
        FOREIGN KEY(id_evento) REFERENCES evento(id_evento)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS mesero (
        id_mesero INTEGER PRIMARY KEY AUTOINCREMENT,
        id_evento INTEGER,
        id_cajero INTEGER,
        nombre TEXT,
        usuario TEXT UNIQUE,
        password TEXT,
        activo INTEGER DEFAULT 1,
        FOREIGN KEY(id_evento) REFERENCES evento(id_evento),
        FOREIGN KEY(id_cajero) REFERENCES cajero(id_cajero)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS categoria_producto (
        id_categoria INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE,
        descripcion TEXT,
        tipo TEXT,
        activo INTEGER DEFAULT 1,
        creado_por_admin INTEGER,
        fecha_creacion TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS producto (
        id_producto INTEGER PRIMARY KEY AUTOINCREMENT,
        id_categoria INTEGER,
        nombre TEXT,
        descripcion TEXT,
        tipo_producto TEXT,
        precio_venta REAL,
        stock_actual INTEGER,
        activo INTEGER DEFAULT 1,
        creado_por_admin INTEGER,
        foto TEXT,
        fecha_creacion TEXT,
        requiere_acompanante INTEGER DEFAULT 0,
        es_acompanante INTEGER DEFAULT 0,
        FOREIGN KEY(id_categoria) REFERENCES categoria_producto(id_categoria)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS comanda (
        id_comanda INTEGER PRIMARY KEY AUTOINCREMENT,
        id_evento INTEGER,
        id_barra INTEGER,
        id_cajero INTEGER,
        id_mesero INTEGER,
        fecha_hora TEXT DEFAULT CURRENT_TIMESTAMP,
        total REAL,
        estado_pago TEXT,
        estatus TEXT,
        observaciones TEXT,
        anulada_por_admin INTEGER NULL,
        fecha_anulacion TEXT NULL,
        motivo_anulacion TEXT NULL,
        clave_idempotencia TEXT,
        FOREIGN KEY(id_evento) REFERENCES evento(id_evento),
        FOREIGN KEY(id_barra) REFERENCES barra(id_barra),
        FOREIGN KEY(id_cajero) REFERENCES cajero(id_cajero),
        FOREIGN KEY(id_mesero) REFERENCES mesero(id_mesero)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_comanda_idempotencia
      ON comanda(clave_idempotencia) WHERE clave_idempotencia IS NOT NULL
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS detalle_comanda (
        id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
        id_comanda INTEGER,
        id_producto INTEGER,
        cantidad INTEGER,
        precio_unitario REAL,
        subtotal REAL,
        id_detalle_padre INTEGER,
        id_promocion INTEGER,
        FOREIGN KEY(id_comanda) REFERENCES comanda(id_comanda) ON DELETE CASCADE,
        FOREIGN KEY(id_producto) REFERENCES producto(id_producto)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS metodo_pago (
        id_metodo_pago INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT UNIQUE,
        descripcion TEXT,
        activo INTEGER DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS pago_comanda (
        id_pago INTEGER PRIMARY KEY AUTOINCREMENT,
        id_comanda INTEGER,
        id_metodo_pago INTEGER,
        monto REAL,
        fecha_hora TEXT DEFAULT CURRENT_TIMESTAMP,
        referencia TEXT,
        estado TEXT,
        FOREIGN KEY(id_comanda) REFERENCES comanda(id_comanda) ON DELETE CASCADE,
        FOREIGN KEY(id_metodo_pago) REFERENCES metodo_pago(id_metodo_pago)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS movimiento_stock (
        id_movimiento INTEGER PRIMARY KEY AUTOINCREMENT,
        id_producto INTEGER,
        id_admin INTEGER,
        tipo_movimiento TEXT,
        cantidad INTEGER,
        stock_anterior INTEGER,
        stock_nuevo INTEGER,
        motivo TEXT,
        fecha_hora TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(id_producto) REFERENCES producto(id_producto),
        FOREIGN KEY(id_admin) REFERENCES administrador_evento(id_admin)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS traspaso (
        id_traspaso INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo TEXT,
        motivo TEXT,
        contraparte TEXT,
        observaciones TEXT,
        id_cajero INTEGER,
        id_admin INTEGER,
        fecha_hora TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS traspaso_detalle (
        id_detalle_traspaso INTEGER PRIMARY KEY AUTOINCREMENT,
        id_traspaso INTEGER,
        id_producto INTEGER,
        cantidad INTEGER,
        FOREIGN KEY(id_traspaso) REFERENCES traspaso(id_traspaso) ON DELETE CASCADE,
        FOREIGN KEY(id_producto) REFERENCES producto(id_producto)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS promocion (
        id_promocion INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT,
        descripcion TEXT,
        precio REAL,
        activa INTEGER DEFAULT 1,
        creada_por_admin INTEGER,
        fecha_creacion TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS promocion_detalle (
        id_detalle_promocion INTEGER PRIMARY KEY AUTOINCREMENT,
        id_promocion INTEGER,
        id_producto INTEGER,
        cantidad INTEGER,
        FOREIGN KEY(id_promocion) REFERENCES promocion(id_promocion) ON DELETE CASCADE,
        FOREIGN KEY(id_producto) REFERENCES producto(id_producto)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS auditoria_admin (
        id_auditoria INTEGER PRIMARY KEY AUTOINCREMENT,
        id_admin INTEGER,
        id_evento INTEGER,
        accion TEXT,
        entidad TEXT,
        id_registro INTEGER,
        detalle TEXT,
        fecha_hora TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(id_admin) REFERENCES administrador_evento(id_admin),
        FOREIGN KEY(id_evento) REFERENCES evento(id_evento)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS impresion_comanda_cajero (
        id_impresion_cajero INTEGER PRIMARY KEY AUTOINCREMENT,
        id_comanda INTEGER,
        id_cajero INTEGER,
        id_mesero INTEGER,
        fecha_hora_impresion TEXT DEFAULT CURRENT_TIMESTAMP,
        numero_copia INTEGER,
        FOREIGN KEY(id_comanda) REFERENCES comanda(id_comanda) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS impresion_comanda_mesero (
        id_impresion_mesero INTEGER PRIMARY KEY AUTOINCREMENT,
        id_comanda INTEGER,
        id_cajero INTEGER,
        id_mesero INTEGER,
        fecha_hora_impresion TEXT DEFAULT CURRENT_TIMESTAMP,
        numero_copia INTEGER,
        FOREIGN KEY(id_comanda) REFERENCES comanda(id_comanda) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS instancia (
        clave TEXT PRIMARY KEY,
        valor TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS configuracion (
        id_configuracion INTEGER PRIMARY KEY CHECK (id_configuracion = 1),
        evento TEXT,
        fecha TEXT,
        lugar TEXT,
        barra TEXT,
        responsable TEXT,
        logo_ticket TEXT
      )
    ''');

    // Tabla de rostros administrativos (Face ID)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS admin_rostro (
        id_rostro INTEGER PRIMARY KEY AUTOINCREMENT,
        id_admin INTEGER,
        nombre TEXT,
        descriptor TEXT,
        foto_referencia TEXT,
        fecha_registro TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(id_admin) REFERENCES administrador_evento(id_admin)
      )
    ''');

    // Índices para rendimiento en consultas frecuentes de ventas
    await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_cajero ON comanda(id_cajero)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_mesero ON comanda(id_mesero)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_estatus ON comanda(estatus)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_fecha ON comanda(fecha_hora)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_comanda ON detalle_comanda(id_comanda)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_producto ON detalle_comanda(id_producto)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_pago_comanda ON pago_comanda(id_comanda)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_movimiento_producto ON movimiento_stock(id_producto)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_producto_categoria ON producto(id_categoria)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_producto_activo ON producto(activo)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cajero_usuario ON cajero(usuario)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_admin_usuario ON administrador_evento(usuario)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_mesero_password ON mesero(password)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rostro_admin ON admin_rostro(id_admin)');

    // Sembrar datos iniciales
    await _seedDatabase(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Agregar tabla admin_rostro si no existe
      await db.execute('''
        CREATE TABLE IF NOT EXISTS admin_rostro (
          id_rostro INTEGER PRIMARY KEY AUTOINCREMENT,
          id_admin INTEGER,
          nombre TEXT,
          descriptor TEXT,
          foto_referencia TEXT,
          fecha_registro TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(id_admin) REFERENCES administrador_evento(id_admin)
        )
      ''');

      // Agregar columnas faltantes si no existen
      try { await db.execute('ALTER TABLE producto ADD COLUMN orden INTEGER DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE producto ADD COLUMN id_botella_vinculada INTEGER'); } catch (_) {}
      try { await db.execute('ALTER TABLE producto ADD COLUMN vasos_por_botella INTEGER DEFAULT 10'); } catch (_) {}
      try { await db.execute('ALTER TABLE categoria_producto ADD COLUMN orden INTEGER DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE configuracion ADD COLUMN logo_ticket TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE promocion ADD COLUMN foto TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE promocion ADD COLUMN precio_combo REAL'); } catch (_) {}
      try { await db.execute('ALTER TABLE promocion ADD COLUMN eliminada INTEGER DEFAULT 0'); } catch (_) {}

      // Índices para rendimiento
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_cajero ON comanda(id_cajero)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_mesero ON comanda(id_mesero)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_estatus ON comanda(estatus)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_comanda_fecha ON comanda(fecha_hora)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_comanda ON detalle_comanda(id_comanda)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_detalle_producto ON detalle_comanda(id_producto)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_pago_comanda ON pago_comanda(id_comanda)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_movimiento_producto ON movimiento_stock(id_producto)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_producto_categoria ON producto(id_categoria)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_producto_activo ON producto(activo)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_cajero_usuario ON cajero(usuario)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_admin_usuario ON administrador_evento(usuario)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_mesero_password ON mesero(password)'); } catch (_) {}
      try { await db.execute('CREATE INDEX IF NOT EXISTS idx_rostro_admin ON admin_rostro(id_admin)'); } catch (_) {}
    }
  }

  Future<void> _seedDatabase(Database db) async {
    final now = nowSql();

    // 1. Instancia & Configuración
    await db.insert('instancia', {'clave': 'nombre', 'valor': 'Barra 1'});
    await db.insert('instancia', {'clave': 'primer_arranque', 'valor': now});

    // 2. Evento
    await db.insert('evento', {
      'id_evento': 1,
      'nombre_evento': 'Festival Sonidos de Verano 2026',
      'fecha_evento': '2026-09-12',
      'lugar': 'Estadio Central',
      'descripcion': 'Evento musical con sistema POS distribuido',
      'hora_inicio': '17:00:00',
      'hora_fin': '02:00:00',
      'activo': 1,
    });

    await db.insert('configuracion', {
      'id_configuracion': 1,
      'evento': 'Festival Sonidos de Verano 2026',
      'fecha': '2026-09-12',
      'lugar': 'Estadio Central',
      'barra': 'Barra 1',
      'responsable': 'Encargado Principal',
    });

    // 3. Barra
    await db.insert('barra', {
      'id_barra': 1,
      'id_evento': 1,
      'nombre_barra': 'Barra 1',
      'descripcion': 'Barra principal del evento',
      'ubicacion': 'Sector Central',
      'activo': 1,
    });
    await db.insert('instancia', {'clave': 'id_barra', 'valor': '1'});

    // 4. Métodos de Pago
    final metodos = [
      {'id_metodo_pago': 1, 'nombre': 'EFECTIVO', 'descripcion': 'Pago en efectivo', 'activo': 1},
      {'id_metodo_pago': 2, 'nombre': 'TARJETA', 'descripcion': 'Pago con tarjeta', 'activo': 1},
      {'id_metodo_pago': 3, 'nombre': 'QR', 'descripcion': 'Pago con código QR', 'activo': 1},
      {'id_metodo_pago': 4, 'nombre': 'TRANSFERENCIA', 'descripcion': 'Transferencia bancaria', 'activo': 1},
    ];
    for (var m in metodos) {
      await db.insert('metodo_pago', m);
    }

    // 5. Administradores
    await db.insert('administrador_evento', {
      'id_admin': 1,
      'id_evento': 1,
      'nombre': 'Administrador Principal',
      'usuario': 'admin_evento',
      'password': 'demo123',
      'rol': 'ADMINISTRADOR',
      'activo': 1,
    });
    await db.insert('administrador_evento', {
      'id_admin': 2,
      'id_evento': 1,
      'nombre': 'Supervisor Operativo',
      'usuario': 'supervisor_evento',
      'password': 'demo123',
      'rol': 'SUPERVISOR',
      'activo': 1,
    });

    // 6. Cajeros
    final cajeros = [
      {'id_cajero': 1, 'id_barra': 1, 'nombre': 'Ana Torres', 'usuario': 'cajero_norte_1', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 2, 'id_barra': 1, 'nombre': 'Luis Mendoza', 'usuario': 'cajero_norte_2', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 3, 'id_barra': 1, 'nombre': 'Carla Rojas', 'usuario': 'cajero_norte_3', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 4, 'id_barra': 1, 'nombre': 'Pedro Vargas', 'usuario': 'cajero_sur_1', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 5, 'id_barra': 1, 'nombre': 'María Fernández', 'usuario': 'cajero_sur_2', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 6, 'id_barra': 1, 'nombre': 'Diego López', 'usuario': 'cajero_sur_3', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 7, 'id_barra': 1, 'nombre': 'Brisa Garcia', 'usuario': 'cajero_general_1', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 8, 'id_barra': 1, 'nombre': 'Jorge Salinas', 'usuario': 'cajero_general_2', 'password': 'demo123', 'activo': 1},
      {'id_cajero': 9, 'id_barra': 1, 'nombre': 'Valeria Quiroga', 'usuario': 'cajero_general_3', 'password': 'demo123', 'activo': 1},
    ];
    for (var c in cajeros) {
      await db.insert('cajero', c);
    }

    // 7. Meseros (45 meseros)
    final nombresMeseros = [
      'Juan Pérez', 'Miguel Flores', 'Sofía Álvarez', 'René Castro', 'Lucía Molina',
      'Mario Gutiérrez', 'Gabriela Soto', 'Andrés Vega', 'Paola Méndez', 'David Arce',
      'Fernando Paz', 'Daniela Cruz', 'Rodrigo Silva', 'Camila Romero', 'Nicolás Suárez',
      'Mateo Ríos', 'Andrea Villarroel', 'Óscar Paredes', 'Natalia León', 'Hugo Cabrera',
      'Marco Aguilar', 'Elena Zamora', 'Pablo Serrano', 'Rocío Chávez', 'Cristian Núñez',
      'Alejandro Ortiz', 'Verónica Lima', 'Martín Céspedes', 'Lorena Ponce', 'Samuel Rocha',
      'Kevin Miranda', 'Isabel Arias', 'Franco Velasco', 'Mónica Durán', 'Esteban Cuéllar',
      'Raúl Guzmán', 'Claudia Peña', 'Iván Mercado', 'Laura Terán', 'Álvaro Rivero',
      'Sergio Blanco', 'Mariana Prado', 'José Valdez', 'Tatiana Roca', 'Carlos Méndez'
    ];
    for (int i = 1; i <= nombresMeseros.length; i++) {
      final cajeroId = ((i - 1) ~/ 5) + 1;
      final u = i < 10 ? '0$i' : '$i';
      await db.insert('mesero', {
        'id_mesero': i,
        'id_evento': 1,
        'id_cajero': cajeroId > 9 ? 1 : cajeroId,
        'nombre': nombresMeseros[i - 1],
        'usuario': 'mesero_$u',
        'password': '${1000 + i}',
        'activo': 1,
      });
    }

    // 8. Categorías
    final categorias = [
      {'id_categoria': 1, 'nombre': 'Cervezas', 'descripcion': 'Cervezas nacionales e importadas', 'tipo': 'BEBIDA', 'activo': 1, 'creado_por_admin': 1, 'fecha_creacion': now},
      {'id_categoria': 2, 'nombre': 'Whiskys', 'descripcion': 'Whiskys servidos por medida o botella', 'tipo': 'BEBIDA', 'activo': 1, 'creado_por_admin': 1, 'fecha_creacion': now},
      {'id_categoria': 3, 'nombre': 'Comida', 'descripcion': 'Comidas rápidas para el evento', 'tipo': 'COMIDA', 'activo': 1, 'creado_por_admin': 1, 'fecha_creacion': now},
      {'id_categoria': 4, 'nombre': 'Refrescos', 'descripcion': 'Bebidas sin alcohol y acompañantes', 'tipo': 'BEBIDA', 'activo': 1, 'creado_por_admin': 1, 'fecha_creacion': now},
    ];
    for (var cat in categorias) {
      await db.insert('categoria_producto', cat);
    }

    // 9. Productos
    final productos = [
      {'id_producto': 1, 'id_categoria': 1, 'nombre': 'Cerveza Paceña 350 ml', 'descripcion': 'Lata individual', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 18.00, 'stock_actual': 120, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 2, 'id_categoria': 1, 'nombre': 'Cerveza Huari 330 ml', 'descripcion': 'Botella individual', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 22.00, 'stock_actual': 95, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 3, 'id_categoria': 1, 'nombre': 'Cerveza Corona 355 ml', 'descripcion': 'Botella individual', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 28.00, 'stock_actual': 70, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 4, 'id_categoria': 1, 'nombre': 'Cerveza Stella Artois 330 ml', 'descripcion': 'Botella individual', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 30.00, 'stock_actual': 60, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 5, 'id_categoria': 1, 'nombre': 'Cerveza Heineken 330 ml', 'descripcion': 'Botella individual', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 29.00, 'stock_actual': 85, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 6, 'id_categoria': 1, 'nombre': 'Cerveza Budweiser 355 ml', 'descripcion': 'Lata individual', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 24.00, 'stock_actual': 90, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 7, 'id_categoria': 1, 'nombre': 'Cerveza artesanal IPA', 'descripcion': 'Vaso 400 ml', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 32.00, 'stock_actual': 45, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 8, 'id_categoria': 2, 'nombre': 'Johnnie Walker Red Label Vaso', 'descripcion': 'Medida 50 ml', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 35.00, 'stock_actual': 38, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 9, 'id_categoria': 2, 'nombre': 'Johnnie Walker Black Label Vaso', 'descripcion': 'Medida 50 ml', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 55.00, 'stock_actual': 30, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 10, 'id_categoria': 2, 'nombre': 'Chivas Regal 12 años Vaso', 'descripcion': 'Medida 50 ml', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 52.00, 'stock_actual': 24, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 11, 'id_categoria': 2, 'nombre': 'Botella Johnnie Walker Red 750ml', 'descripcion': 'Botella entera con 2 refrescos a elección', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 320.00, 'stock_actual': 15, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 1, 'es_acompanante': 0},
      {'id_producto': 12, 'id_categoria': 2, 'nombre': 'Botella Johnnie Walker Black 750ml', 'descripcion': 'Botella entera con 2 refrescos a elección', 'tipo_producto': 'BEBIDA_ALCOHOLICA', 'precio_venta': 480.00, 'stock_actual': 12, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 1, 'es_acompanante': 0},
      {'id_producto': 13, 'id_categoria': 3, 'nombre': 'Hamburguesa clásica', 'descripcion': 'Carne, queso, lechuga y tomate', 'tipo_producto': 'COMIDA', 'precio_venta': 38.00, 'stock_actual': 55, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 14, 'id_categoria': 3, 'nombre': 'Hamburguesa doble', 'descripcion': 'Doble carne y doble queso', 'tipo_producto': 'COMIDA', 'precio_venta': 52.00, 'stock_actual': 42, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 15, 'id_categoria': 3, 'nombre': 'Hot Dog especial', 'descripcion': 'Salchicha alemana, papas y salsas', 'tipo_producto': 'COMIDA', 'precio_venta': 25.00, 'stock_actual': 65, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 16, 'id_categoria': 3, 'nombre': 'Papas fritas rústicas', 'descripcion': 'Porción mediana', 'tipo_producto': 'COMIDA', 'precio_venta': 18.00, 'stock_actual': 80, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 17, 'id_categoria': 4, 'nombre': 'Coca Cola 2L', 'descripcion': 'Botella 2L acompañante o individual', 'tipo_producto': 'BEBIDA', 'precio_venta': 18.00, 'stock_actual': 100, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 1},
      {'id_producto': 18, 'id_categoria': 4, 'nombre': 'Sprite 2L', 'descripcion': 'Botella 2L acompañante o individual', 'tipo_producto': 'BEBIDA', 'precio_venta': 18.00, 'stock_actual': 80, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 1},
      {'id_producto': 19, 'id_categoria': 4, 'nombre': 'Agua Mineral 500ml', 'descripcion': 'Agua sin gas', 'tipo_producto': 'BEBIDA', 'precio_venta': 10.00, 'stock_actual': 120, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 0},
      {'id_producto': 20, 'id_categoria': 4, 'nombre': 'Red Bull 250ml', 'descripcion': 'Energizante', 'tipo_producto': 'BEBIDA', 'precio_venta': 25.00, 'stock_actual': 90, 'activo': 1, 'creado_por_admin': 1, 'requiere_acompanante': 0, 'es_acompanante': 1},
    ];

    for (var prod in productos) {
      final pMap = Map<String, dynamic>.from(prod);
      pMap['fecha_creacion'] = now;
      await db.insert('producto', pMap);

      // Movimiento inicial de stock
      final stock = prod['stock_actual'] as int;
      if (stock > 0) {
        await db.insert('movimiento_stock', {
          'id_producto': prod['id_producto'],
          'id_admin': 1,
          'tipo_movimiento': 'ENTRADA',
          'cantidad': stock,
          'stock_anterior': 0,
          'stock_nuevo': stock,
          'motivo': 'Carga inicial de stock para el evento',
          'fecha_hora': now,
        });
      }
    }

    // 10. Promoción de ejemplo
    final promoId = await db.insert('promocion', {
      'id_promocion': 1,
      'nombre': 'Combo Amigos: 4 Paceñas + Papas',
      'descripcion': '4 latas Paceña 350ml + 1 Porción de Papas fritas rústicas',
      'precio': 75.00,
      'activa': 1,
      'creada_por_admin': 1,
      'fecha_creacion': now,
    });
    await db.insert('promocion_detalle', {
      'id_promocion': promoId,
      'id_producto': 1, // Paceña
      'cantidad': 4,
    });
    await db.insert('promocion_detalle', {
      'id_promocion': promoId,
      'id_producto': 16, // Papas
      'cantidad': 1,
    });

    // 11. Auditoría inicial
    await db.insert('auditoria_admin', {
      'id_admin': 1,
      'id_evento': 1,
      'accion': 'INICIALIZAR_SISTEMA',
      'entidad': 'sistema',
      'id_registro': 1,
      'detalle': 'Inicialización de base de datos nativa MasterDrinks Flutter',
      'fecha_hora': now,
    });
  }
}
