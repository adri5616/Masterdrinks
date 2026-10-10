import 'package:flutter/material.dart';
import '../data/models/models.dart';
import '../services/api_service.dart';

class PosProvider extends ChangeNotifier {
  List<CategoryModel> _categories = [];
  List<ProductModel> _products = [];
  List<PromotionModel> _promotions = [];
  EventConfigModel? _eventConfig;

  int? _selectedCategoryId; // null = Todas las categorías
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;

  List<CategoryModel> get categories => _categories;
  List<ProductModel> get products => _products;
  List<PromotionModel> get promotions => _promotions;
  EventConfigModel? get eventConfig => _eventConfig;
  int? get selectedCategoryId => _selectedCategoryId;
  String get searchQuery => _searchQuery;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<ProductModel> get companions {
    return _products.where((p) => p.esAcompanante && p.stockActual > 0).toList();
  }

  List<dynamic> get filteredItems {
    final List<dynamic> list = [];

    // Si está seleccionada la categoría "Promociones" o "Todas"
    if (_selectedCategoryId == -99 || _selectedCategoryId == null) {
      for (var promo in _promotions) {
        if (_searchQuery.isEmpty || promo.nombre.toLowerCase().contains(_searchQuery.toLowerCase())) {
          list.add(promo);
        }
      }
    }

    if (_selectedCategoryId != -99) {
      for (var p in _products) {
        if (_selectedCategoryId != null && p.idCategoria != _selectedCategoryId) {
          continue;
        }
        if (_searchQuery.isNotEmpty && !p.nombre.toLowerCase().contains(_searchQuery.toLowerCase())) {
          continue;
        }
        list.add(p);
      }
    }

    return list;
  }

  void setSelectedCategory(int? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadCatalog() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final config = await ApiService.instance.getConfiguracion();
      _eventConfig = config;

      final data = await ApiService.instance.getProductosYCategorias();
      final catList = (data['categorias'] as List? ?? [])
          .map((c) => CategoryModel.fromMap(c as Map<String, dynamic>))
          .toList();
      final prodList = (data['productos'] as List? ?? [])
          .map((p) => ProductModel.fromMap(p as Map<String, dynamic>))
          .toList();

      final promoList = (data['promociones'] as List? ?? []).map((pr) {
        final prMap = pr as Map<String, dynamic>;
        final items = (prMap['items'] as List? ?? []).map((it) {
          final itMap = it as Map<String, dynamic>;
          return PromoItemModel(
            idProducto: itMap['id_producto'] as int,
            nombreProducto: itMap['nombre'] as String,
            cantidad: itMap['cantidad'] as int,
            precioCatalogo: (itMap['precio_venta'] is num) ? (itMap['precio_venta'] as num).toDouble() : 0.0,
          );
        }).toList();
        return PromotionModel.fromMap(prMap, items);
      }).toList();

      _categories = catList;
      _products = prodList;
      _promotions = promoList;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error cargando catálogo: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStock() async {
    try {
      final stockData = await ApiService.instance.getStock();
      final stockMap = {for (var item in stockData) item['id_producto'] as int: item['stock_actual'] as int};

      _products = _products.map((p) {
        final newStock = stockMap[p.idProducto] ?? p.stockActual;
        return ProductModel(
          idProducto: p.idProducto,
          idCategoria: p.idCategoria,
          nombre: p.nombre,
          descripcion: p.descripcion,
          tipoProducto: p.tipoProducto,
          precioVenta: p.precioVenta,
          stockActual: newStock,
          activo: p.activo,
          foto: p.foto,
          requiereAcompanante: p.requiereAcompanante,
          esAcompanante: p.esAcompanante,
        );
      }).toList();
      notifyListeners();
    } catch (_) {}
  }
}
