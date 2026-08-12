import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/store_settings.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class CartProvider extends ChangeNotifier {
  List<CartItem> _items = [];
  StoreSettings _settings = StoreSettings();
  bool _loading = false;
  bool _isLoggedIn = false;
  bool _authInitialized = false;

  Future<void> initAuthState() async {
    if (_authInitialized) return;
    _authInitialized = true;
    final loggedIn = await AuthService.isLoggedIn();
    if (loggedIn) {
      _isLoggedIn = true;
      try {
        await _fetchFromBackend();
      } catch (_) {
        _loading = false;
      }
      notifyListeners();
    }
  }

  List<CartItem> get items => _items;
  StoreSettings get settings => _settings;
  bool get loading => _loading;
  bool get isLoggedIn => _isLoggedIn;
  int get itemCount => _items.length;

  double get subtotal =>
      _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get deliveryCharge =>
      subtotal >= _settings.freeDeliveryThreshold ? 0.0 : _settings.deliveryCharge;

  double get grandTotal => subtotal + deliveryCharge;

  bool get isCartEmpty => _items.isEmpty;

  void setLoggedIn(bool value) {
    _isLoggedIn = value;
    notifyListeners();
  }

  // ─── Add (handles local + backend) ───────────────────────

  void addItem(dynamic source, {double? quantity}) {
    final productId = source is Product ? source.id : source.productId;
    final subProductId = source is CartItem ? source.subProductId : null;
    final orderStep = source is Product ? source.orderStep : (source is CartItem ? source.orderStep : 1.0);
    final minOrderQty = source is Product ? source.minOrderQty : (source is CartItem ? source.minOrderQty : 0.0);
    final price = source is Product ? source.price : (source is CartItem ? source.price : 0.0);
    final name = source is Product ? source.name : (source is CartItem ? source.name : '');
    final image = source is Product ? source.imageUrl : (source is CartItem ? source.image : null);
    final unit = source is Product ? source.unit : (source is CartItem ? source.unit : null);
    final taxPercentage = source is Product ? source.taxPercentage : (source is CartItem ? source.taxPercentage : 0.0);

    final key = subProductId != null ? 's_${productId}_$subProductId' : 'p_$productId';
    final initialQty = quantity ?? (minOrderQty > 0 ? minOrderQty : orderStep);
    
    final index = _items.indexWhere((i) => i.cartKey == key);
    if (index >= 0) {
      _items[index].quantity += quantity ?? orderStep;
    } else {
      _items.add(CartItem(
        productId: productId,
        subProductId: subProductId,
        name: name,
        price: price,
        image: image,
        unit: unit,
        quantity: initialQty,
        taxPercentage: taxPercentage,
        orderStep: orderStep,
        minOrderQty: minOrderQty,
      ));
    }
    _persist();
    notifyListeners();
  }

  Future<void> addToBackend(dynamic source, {double? quantity}) async {
    final productId = source is Product ? source.id : source.productId;
    final orderStep = source is Product ? source.orderStep : (source is CartItem ? source.orderStep : 1.0);
    final minOrderQty = source is Product ? source.minOrderQty : (source is CartItem ? source.minOrderQty : 0.0);
    final initialQty = quantity ?? (minOrderQty > 0 ? minOrderQty : orderStep);

    // Optimistic UI update
    addItem(source, quantity: initialQty);

    if (!_isLoggedIn) {
      return;
    }

    // Fire and forget backend sync
    _syncAddToBackend(productId, initialQty);
  }

  Future<void> _syncAddToBackend(int productId, double quantity) async {
    try {
      await ApiService.addToCart(productId, quantity);
      await _fetchFromBackend(silent: true);
    } catch (_) {
      // Re-sync on failure
      await _fetchFromBackend(silent: true);
    }
  }

  // ─── Update quantity ─────────────────────────────────────

  Future<void> updateQuantity(int productId, double quantity, {int? subProductId}) async {
    final key = subProductId != null ? 's_${productId}_$subProductId' : 'p_$productId';
    
    // Optimistic UI update
    _updateLocalQuantity(key, quantity);

    if (_isLoggedIn) {
      // Fire and forget backend sync
      _syncUpdateQuantity(productId, quantity);
    }
  }

  Future<void> _syncUpdateQuantity(int productId, double quantity) async {
    try {
      if (quantity <= 0) {
        await ApiService.removeFromCart(productId);
      } else {
        await ApiService.addToCart(productId, quantity);
      }
      await _fetchFromBackend(silent: true);
    } catch (_) {
      // Re-sync on failure
      await _fetchFromBackend(silent: true);
    }
  }

  void _updateLocalQuantity(String key, double quantity) {
    final index = _items.indexWhere((i) => i.cartKey == key);
    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      _persist();
      notifyListeners();
    }
  }

  // ─── Remove ──────────────────────────────────────────────

  Future<void> removeFromBackend(int productId, {int? subProductId}) async {
    final key = subProductId != null ? 's_${productId}_$subProductId' : 'p_$productId';
    
    // Optimistic UI update
    _removeLocal(key);

    if (_isLoggedIn) {
      // Fire and forget backend sync
      _syncRemoveFromBackend(productId);
    }
  }

  Future<void> _syncRemoveFromBackend(int productId) async {
    try {
      await ApiService.removeFromCart(productId);
      await _fetchFromBackend(silent: true);
    } catch (_) {
      // Re-sync on failure
      await _fetchFromBackend(silent: true);
    }
  }

  void _removeLocal(String key) {
    _items.removeWhere((i) => i.cartKey == key);
    _persist();
    notifyListeners();
  }

  // ─── Clear ───────────────────────────────────────────────

  Future<void> clearBackendCart() async {
    if (_isLoggedIn) {
      try {
        await ApiService.clearCart();
      } catch (_) {}
    }
    _items.clear();
    _persist();
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    _authInitialized = false;
    _items.clear();
    loadGuestCart();
  }

  // ─── Sync after login ────────────────────────────────────

  Future<void> syncAfterLogin() async {
    _isLoggedIn = true;
    final localItems = List<CartItem>.from(_items);
    if (localItems.isNotEmpty) {
      try {
        await ApiService.mergeCart(
          localItems.map((i) => i.toJson()).toList(),
        );
      } catch (_) {}
    }
    try {
      await _fetchFromBackend();
    } catch (_) {}
  }

  // ─── Fetch from backend ──────────────────────────────────

  Future<void> fetchCart() async {
    if (_isLoggedIn) {
      try {
        await _fetchFromBackend();
      } catch (_) {
        _loading = false;
        notifyListeners();
      }
    } else {
      await loadGuestCart();
    }
  }

  Future<void> _fetchFromBackend({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      notifyListeners();
    }
    try {
      _items = await ApiService.fetchCart();
      _clearGuestCart();
    } finally {
      if (!silent) {
        _loading = false;
      }
      notifyListeners();
    }
  }

  // ─── Guest cart (local) ──────────────────────────────────

  Future<void> loadGuestCart() async {
    final prefs = await SharedPreferences.getInstance();
    final cart = prefs.getString('guest_cart');
    if (cart != null) {
      final list = json.decode(cart) as List;
      _items = list.map((i) => CartItem.fromJson(i)).toList();
      notifyListeners();
    }
  }

  void _persist() {
    if (_isLoggedIn) return;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
          'guest_cart', json.encode(_items.map((i) => i.toJson()).toList()));
    });
  }

  void _clearGuestCart() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('guest_cart');
    });
  }

  // ─── Store settings ──────────────────────────────────────

  Future<void> fetchStoreSettings() async {
    try {
      _settings = await ApiService.fetchStoreSettings();
      notifyListeners();
    } catch (_) {}
  }
}
