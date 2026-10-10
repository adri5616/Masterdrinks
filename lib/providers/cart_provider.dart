import 'dart:math';
import 'package:flutter/material.dart';
import '../data/models/models.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItemModel> _items = [];
  String _idempotencyKey = _newIdempotencyKey();

  List<CartItemModel> get items => List.unmodifiable(_items);
  String get idempotencyKey => _idempotencyKey;

  static String _newIdempotencyKey() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rnd = Random().nextInt(999999);
    return 'tx_${now}_$rnd';
  }

  void refreshIdempotencyKey() {
    _idempotencyKey = _newIdempotencyKey();
    notifyListeners();
  }

  int get totalItemsCount {
    return _items.fold(0, (sum, i) => sum + i.cantidad);
  }

  double get totalAmount {
    return _items.fold(0.0, (sum, i) => sum + i.subtotal);
  }

  void addProduct(ProductModel product, {ProductModel? acompanante}) {
    // Si ya existe en el carrito con el mismo acompañante, sumar cantidad
    final idx = _items.indexWhere((item) =>
      !item.isPromo &&
      item.product?.idProducto == product.idProducto &&
      item.acompanante?.idProducto == acompanante?.idProducto
    );

    if (idx != -1) {
      _items[idx].cantidad++;
    } else {
      _items.add(CartItemModel(
        product: product,
        cantidad: 1,
        acompanante: acompanante,
      ));
    }
    notifyListeners();
  }

  void addPromotion(PromotionModel promo) {
    final idx = _items.indexWhere((item) => item.isPromo && item.promo?.idPromocion == promo.idPromocion);
    if (idx != -1) {
      _items[idx].cantidad++;
    } else {
      _items.add(CartItemModel(
        promo: promo,
        cantidad: 1,
      ));
    }
    notifyListeners();
  }

  void incrementQuantity(int index) {
    if (index >= 0 && index < _items.length) {
      _items[index].cantidad++;
      notifyListeners();
    }
  }

  void decrementQuantity(int index) {
    if (index >= 0 && index < _items.length) {
      if (_items[index].cantidad > 1) {
        _items[index].cantidad--;
      } else {
        _items.removeAt(index);
      }
      notifyListeners();
    }
  }

  void removeItem(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    refreshIdempotencyKey();
    notifyListeners();
  }
}
