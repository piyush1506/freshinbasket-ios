class CartItem {
  final int? id;
  final int productId;
  final int? subProductId;
  final String name;
  final double price;
  final String? image;
  final String? unit;
  double quantity;
  final double taxPercentage;
  final double orderStep;
  final double minOrderQty;

  CartItem({
    this.id,
    required this.productId,
    this.subProductId,
    required this.name,
    required this.price,
    this.image,
    this.unit,
    this.quantity = 1.0,
    this.taxPercentage = 0.0,
    this.orderStep = 1.0,
    this.minOrderQty = 0.0,
  });

  double get totalPrice => price * quantity;
  String get cartKey => subProductId != null ? 's_${productId}_$subProductId' : 'p_$productId';

  static double _toDouble(dynamic v, {double fallback = 0.0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }



  factory CartItem.fromJson(Map<String, dynamic> json) {
    final product = json['product'] is Map ? json['product'] as Map : null;
    final unitMap = json['unit'] is Map ? json['unit'] as Map : null;
    return CartItem(
      id: json['id'],
      productId: product != null
          ? product['id'] ?? json['product_id']
          : (json['product'] ?? json['product_id']),
      subProductId: json['sub_product'] is Map
          ? json['sub_product']['id']
          : (json['sub_product_id'] ?? json['sub_product']),
      name: product?['name'] ?? json['name'] ?? json['product_name'] ?? '',
      price: _toDouble(product?['price'] ?? json['price'] ?? json['unit_price']),
      image: product?['image'] ?? json['product_image_url'] ?? json['image'] ?? json['image_url'],
      unit: unitMap?['name'] ?? product?['unit'] ?? json['unit'] ?? json['unit_name'],
      quantity: _toDouble(json['quantity'], fallback: 1.0),
      taxPercentage: _toDouble(json['tax_percentage']),
      orderStep: _toDouble(json['order_step'], fallback: 1.0),
      minOrderQty: _toDouble(json['min_order_qty']),
    );
  }

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    if (subProductId != null) 'sub_product_id': subProductId,
    'name': name,
    'price': price,
    'image': image,
    'unit': unit,
    'quantity': quantity,
  };
}
