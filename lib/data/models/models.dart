class UserModel {
  final int id;
  final String nombre;
  final String usuario;
  final String rol; // 'CAJERO', 'ADMINISTRADOR', 'SUPERVISOR', 'MESERO'
  final int? idBarra;
  final int? idCajero; // Si es mesero

  UserModel({
    required this.id,
    required this.nombre,
    required this.usuario,
    required this.rol,
    this.idBarra,
    this.idCajero,
  });

  bool get isAdmin => rol == 'ADMINISTRADOR' || rol == 'SUPERVISOR';
  bool get isCajero => rol == 'CAJERO';
  bool get isMesero => rol == 'MESERO';

  factory UserModel.fromMap(Map<String, dynamic> map, String defaultRole) {
    return UserModel(
      id: (map['id_cajero'] ?? map['id_admin'] ?? map['id_mesero'] ?? 0) as int,
      nombre: (map['nombre'] ?? '') as String,
      usuario: (map['usuario'] ?? '') as String,
      rol: (map['rol'] ?? defaultRole) as String,
      idBarra: map['id_barra'] as int?,
      idCajero: map['id_cajero'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'nombre': nombre,
    'usuario': usuario,
    'rol': rol,
    'id_barra': idBarra,
    'id_cajero': idCajero,
  };
}

class WaiterModel {
  final int idMesero;
  final String nombre;
  final String usuario;
  final String pin;
  final int idCajero;
  final int activo;

  WaiterModel({
    required this.idMesero,
    required this.nombre,
    required this.usuario,
    required this.pin,
    required this.idCajero,
    this.activo = 1,
  });

  factory WaiterModel.fromMap(Map<String, dynamic> map) {
    return WaiterModel(
      idMesero: (map['id_mesero'] ?? 0) as int,
      nombre: (map['nombre'] ?? '') as String,
      usuario: (map['usuario'] ?? '') as String,
      pin: (map['password'] ?? '') as String,
      idCajero: (map['id_cajero'] ?? 0) as int,
      activo: (map['activo'] ?? 1) as int,
    );
  }
}

class CategoryModel {
  final int idCategoria;
  final String nombre;
  final String? descripcion;
  final String? tipo;
  final int activo;

  CategoryModel({
    required this.idCategoria,
    required this.nombre,
    this.descripcion,
    this.tipo,
    this.activo = 1,
  });

  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      idCategoria: (map['id_categoria'] ?? 0) as int,
      nombre: (map['nombre'] ?? '') as String,
      descripcion: map['descripcion'] as String?,
      tipo: map['tipo'] as String?,
      activo: (map['activo'] ?? 1) as int,
    );
  }
}

class ProductModel {
  final int idProducto;
  final int idCategoria;
  final String nombre;
  final String? descripcion;
  final String? tipoProducto;
  final double precioVenta;
  final int stockActual;
  final int activo;
  final String? foto;
  final bool requiereAcompanante;
  final bool esAcompanante;

  ProductModel({
    required this.idProducto,
    required this.idCategoria,
    required this.nombre,
    this.descripcion,
    this.tipoProducto,
    required this.precioVenta,
    required this.stockActual,
    this.activo = 1,
    this.foto,
    this.requiereAcompanante = false,
    this.esAcompanante = false,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      idProducto: (map['id_producto'] ?? 0) as int,
      idCategoria: (map['id_categoria'] ?? 0) as int,
      nombre: (map['nombre'] ?? '') as String,
      descripcion: map['descripcion'] as String?,
      tipoProducto: map['tipo_producto'] as String?,
      precioVenta: (map['precio_venta'] is num) ? (map['precio_venta'] as num).toDouble() : 0.0,
      stockActual: (map['stock_actual'] ?? 0) as int,
      activo: (map['activo'] ?? 1) as int,
      foto: map['foto'] as String?,
      requiereAcompanante: (map['requiere_acompanante'] == 1 || map['requiere_acompanante'] == true),
      esAcompanante: (map['es_acompanante'] == 1 || map['es_acompanante'] == true),
    );
  }
}

class PromoItemModel {
  final int idProducto;
  final String nombreProducto;
  final int cantidad;
  final double precioCatalogo;

  PromoItemModel({
    required this.idProducto,
    required this.nombreProducto,
    required this.cantidad,
    required this.precioCatalogo,
  });
}

class PromotionModel {
  final int idPromocion;
  final String nombre;
  final String? descripcion;
  final double precio;
  final int activa;
  final List<PromoItemModel> items;

  PromotionModel({
    required this.idPromocion,
    required this.nombre,
    this.descripcion,
    required this.precio,
    this.activa = 1,
    this.items = const [],
  });

  factory PromotionModel.fromMap(Map<String, dynamic> map, [List<PromoItemModel>? items]) {
    return PromotionModel(
      idPromocion: (map['id_promocion'] ?? 0) as int,
      nombre: (map['nombre'] ?? '') as String,
      descripcion: map['descripcion'] as String?,
      precio: (map['precio'] is num) ? (map['precio'] as num).toDouble() : 0.0,
      activa: (map['activa'] ?? 1) as int,
      items: items ?? [],
    );
  }
}

class CartItemModel {
  final ProductModel? product;
  final PromotionModel? promo;
  int cantidad;
  ProductModel? acompanante; // Refresco o mezclador asignado

  CartItemModel({
    this.product,
    this.promo,
    this.cantidad = 1,
    this.acompanante,
  }) : assert(product != null || promo != null);

  bool get isPromo => promo != null;
  String get name => isPromo ? promo!.nombre : product!.nombre;
  double get unitPrice => isPromo ? promo!.precio : product!.precioVenta;
  double get subtotal => unitPrice * cantidad;
  int? get idProducto => product?.idProducto;
  int? get idPromocion => promo?.idPromocion;
}

class PaymentSplit {
  final String metodo; // 'EFECTIVO', 'QR', 'TARJETA', 'TRANSFERENCIA'
  final double monto;
  final String? referencia;

  PaymentSplit({
    required this.metodo,
    required this.monto,
    this.referencia,
  });
}

class EventConfigModel {
  final String evento;
  final String fecha;
  final String lugar;
  final String barra;
  final String responsable;

  EventConfigModel({
    required this.evento,
    required this.fecha,
    required this.lugar,
    required this.barra,
    required this.responsable,
  });

  factory EventConfigModel.fromMap(Map<String, dynamic> map) {
    return EventConfigModel(
      evento: (map['evento'] ?? 'MasterDrinks Evento') as String,
      fecha: (map['fecha'] ?? '') as String,
      lugar: (map['lugar'] ?? '') as String,
      barra: (map['barra'] ?? 'Barra 1') as String,
      responsable: (map['responsable'] ?? '') as String,
    );
  }
}
