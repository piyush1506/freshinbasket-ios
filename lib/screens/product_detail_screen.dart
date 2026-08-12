import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/product.dart';
import '../models/sub_product.dart';
import '../models/category.dart';
import '../models/cart_item.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/product_card.dart';
import 'package:share_plus/share_plus.dart';

class ProductDetailScreen extends StatefulWidget {
  final int productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Future<Product> _productFuture;
  late Future<List<Product>> _relatedFuture;
  late Future<List<Category>> _categoriesFuture;
  double _quantity = 1.0;
  SubProduct? _selectedSub;
  bool _adding = false;
  bool _quantityInitialized = false;
  bool _isDescExpanded = false;

  @override
  void initState() {
    super.initState();
    _productFuture = ApiService.fetchProduct(widget.productId);
    _relatedFuture = _fetchRelated();
    _categoriesFuture = ApiService.fetchCategories();
  }

  Future<List<Product>> _fetchRelated() async {
    try {
      final product = await ApiService.fetchProduct(widget.productId);
      final all = await ApiService.fetchProducts();
      final catNames = product.categoryNames;
      return all.where((p) {
        if (p.id == widget.productId) return false;
        return p.categoryNames.any((c) => catNames.contains(c));
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<Product>(
        future: _productFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final product = snapshot.data!;
          final activeImg = _selectedSub?.imageUrl ?? product.imageUrl;
          final activeName = _selectedSub != null ? '${product.name} - ${_selectedSub!.name}' : product.name;
          final activePrice = _selectedSub?.price ?? product.price;
          final activeMrp = _selectedSub?.mrp ?? product.mrp;
          final activeStock = _selectedSub?.stock ?? product.stock;
          final activeUnit = _selectedSub?.unit ?? product.unit;
          final activeDesc = _selectedSub?.description ?? product.description;
          final activeDisc = _selectedSub?.discountPercentage ?? product.discountPercentage;
          final inStock = activeStock > 0;
          final cart = context.watch<CartProvider>();
          final cartItem = cart.items.where((i) {
            if (_selectedSub != null) return i.productId == product.id && i.subProductId == _selectedSub!.id;
            return i.productId == product.id;
          }).firstOrNull;

          final activeStep = product.orderStep;
          final minQty = product.minOrderQty;
          final actualMin = minQty > 0 ? minQty : activeStep;

          // Initialize quantity from backend data exactly once
          if (!_quantityInitialized) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _quantity = cartItem != null ? cartItem.quantity : actualMin;
                  _quantityInitialized = true;
                });
              }
            });
          }

          return CustomScrollView(
            slivers: [
              // ── Full-bleed image sliver app bar ──
              SliverAppBar(
                expandedHeight: 320,
                pinned: true,
                stretch: true,
                backgroundColor: Colors.white,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircleAvatar(
                    backgroundColor: Colors.black26,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircleAvatar(
                      backgroundColor: Colors.black26,
                      child: IconButton(
                        icon: const Icon(Icons.share, color: Colors.white, size: 20),
                        onPressed: () => _shareProduct(product),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Consumer<WishlistProvider>(
                      builder: (context, wishlist, _) {
                        final isWishlisted = wishlist.isWishlisted(widget.productId);
                        return CircleAvatar(
                          backgroundColor: Colors.black26,
                          child: IconButton(
                            icon: Icon(
                              isWishlisted ? Icons.favorite : Icons.favorite_border,
                              color: isWishlisted ? const Color(0xFFE57373) : Colors.white,
                            ),
                            onPressed: () {
                              final auth = context.read<AuthProvider>();
                              if (!auth.isLoggedIn) {
                                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Please log in to manage your wishlist.'),
                                    duration: const Duration(seconds: 2),
                                    action: SnackBarAction(
                                      label: 'Log In',
                                      onPressed: () => Navigator.pushNamed(context, '/auth'),
                                    ),
                                  ),
                                );
                                return;
                              }
                              wishlist.toggle(widget.productId);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8, right: 12, left: 8),
                    child: Consumer<CartProvider>(
                      builder: (context, cart, _) {
                        return CircleAvatar(
                          backgroundColor: Colors.black26,
                          child: IconButton(
                            icon: Badge(
                              isLabelVisible: cart.itemCount > 0,
                              label: Text(cart.itemCount > 99 ? '99+' : '${cart.itemCount}'),
                              child: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 20),
                            ),
                            onPressed: () {
                              Navigator.pushNamed(context, '/cart');
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Container(
                    color: Colors.white,
                    child: activeImg != null
                        ? CachedNetworkImage(
                            imageUrl: activeImg.startsWith('http')
                                ? activeImg
                                : '${ApiService.baseUrl}$activeImg',
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                            memCacheWidth: 1080, // cache at device pixel width for sharpness
                            placeholder: (_, __) => Container(
                              color: const Color(0xFFF5F5F5),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.grey.shade100,
                              child: const Icon(Icons.image, size: 80, color: Colors.grey),
                            ),
                          )
                        : Container(
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.image, size: 80, color: Colors.grey),
                          ),
                  ),
                ),
              ),

              // ── Content card below image ──
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F8F5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sub-product selector
                      if (product.hasSubproducts)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: _buildSubProductSelector(product, cart),
                        ),

                      // Main info card
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Category chips + stock badge
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                ...product.categoryNames.take(2).map((cat) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(cat, style: const TextStyle(fontSize: 11, color: Color(0xFF164431), fontWeight: FontWeight.w600)),
                                )),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: inStock ? Colors.green.shade50 : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    inStock ? 'In Stock' : 'Sold Out',
                                    style: TextStyle(
                                      color: inStock ? const Color(0xFF164431) : Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Product name
                            Text(activeName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                            if (activeUnit != null) ...[
                              const SizedBox(height: 4),
                              Text('Per $activeUnit', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                            ],
                            const SizedBox(height: 14),

                            // Price row
                            Row(
                              children: [
                                Text('₹${activePrice.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 26, color: Color(0xFF164431), fontWeight: FontWeight.bold)),
                                if (activeMrp > activePrice) ...[
                                  const SizedBox(width: 8),
                                  Text('₹${activeMrp.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 16, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                                ],
                                if (activeDisc > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: const Color(0xFF164431), borderRadius: BorderRadius.circular(6)),
                                    child: Text('${activeDisc.round()}% OFF', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),

                            if (product.taxPercentage > 0) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                                child: Text('+${product.taxPercentage.round()}% tax applicable',
                                    style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Description card
                      if (activeDesc.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Description', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Builder(
                                builder: (context) {
                                  final words = activeDesc.split(RegExp(r'\s+'));
                                  final isLong = words.length > 100;
                                  final displayDesc = (isLong && !_isDescExpanded) 
                                      ? '${words.take(100).join(' ')}...' 
                                      : activeDesc;
                                      
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(displayDesc, style: TextStyle(color: Colors.grey[700], height: 1.6, fontSize: 14)),
                                      if (isLong) ...[
                                        const SizedBox(height: 8),
                                        GestureDetector(
                                          onTap: () => setState(() => _isDescExpanded = !_isDescExpanded),
                                          child: Text(
                                            _isDescExpanded ? 'See less' : 'See more',
                                            style: const TextStyle(color: Color(0xFF164431), fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                      // Quantity + Add to cart card
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text('Quantity', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                const Spacer(),
                                _quantityControl(activeStep, actualMin, activeUnit),
                              ],
                            ),
                            if (activeStep != 1.0) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Step: ${_formatQty(activeStep)} ${activeUnit ?? ''} per tap',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                              ),
                            ],
                            if (cartItem != null) ...[
                              const SizedBox(height: 6),
                              Text('${_formatQty(cartItem.quantity)} ${activeUnit ?? ''} already in cart',
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF164431), fontWeight: FontWeight.w500)),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: inStock && !_adding
                                    ? () => _addToCart(product, cart, cartItem)
                                    : null,
                                icon: const Icon(Icons.add_shopping_cart),
                                label: Text(_adding ? 'Adding...' : cartItem != null ? 'Update Cart' : 'Add to Cart'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF164431),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            if (cartItem != null) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton.icon(
                                  onPressed: () {
                                    cart.removeFromBackend(product.id, subProductId: _selectedSub?.id);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Removed from cart'), behavior: SnackBarBehavior.floating),
                                    );
                                  },
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  label: const Text('Remove from cart', style: TextStyle(color: Colors.red)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Related products
                      FutureBuilder<List<Product>>(
                        future: _relatedFuture,
                        builder: (context, snap) {
                          if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Related Products', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                GridView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 8,
                                    mainAxisExtent: 210,
                                  ),
                                  itemCount: snap.data!.length,
                                  itemBuilder: (context, index) {
                                    return ProductCard(product: snap.data![index], isHorizontal: false);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // Random Products (40-50)
                      FutureBuilder<List<Category>>(
                        future: _categoriesFuture,
                        builder: (context, catSnap) {
                          if (!catSnap.hasData || catSnap.data!.isEmpty) return const SizedBox.shrink();
                          
                          // Extract all products from all categories
                          final Map<int, Product> uniqueProducts = {};
                          for (final cat in catSnap.data!) {
                            for (final p in cat.products) {
                              if (p.id != widget.productId) {
                                uniqueProducts[p.id] = p;
                              }
                            }
                          }
                          
                          if (uniqueProducts.isEmpty) return const SizedBox.shrink();

                          final allProducts = uniqueProducts.values.toList();
                          // Stable shuffle based on the current product ID so it doesn't reshuffle on setState
                          allProducts.shuffle(Random(widget.productId));
                          final displayProducts = allProducts.take(50).toList();

                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('More Products to Explore', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                GridView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 8,
                                    mainAxisExtent: 210,
                                  ),
                                  itemCount: displayProducts.length,
                                  itemBuilder: (context, index) {
                                    return ProductCard(product: displayProducts[index], isHorizontal: false);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSubProductSelector(Product product, CartProvider cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select Variety:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF444444))),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: product.subproducts.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                final selected = _selectedSub == null;
                return _variantChip(product.name, product.imageUrl, product.id, null, selected, cart, forProduct: product);
              }
              final sub = product.subproducts[index - 1];
              final selected = _selectedSub?.id == sub.id;
              return _variantChip(sub.name, sub.imageUrl, product.id, sub.id, selected, cart, forProduct: product);
            },
          ),
        ),
      ],
    );
  }

  Widget _variantChip(String name, String? imgUrl, int productId, int? subId, bool selected, CartProvider cart, {Product? forProduct}) {
    final cartItem = cart.items.where((i) =>
      i.productId == productId && i.subProductId == subId
    ).firstOrNull;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSub = subId != null && forProduct != null
              ? (forProduct.subproducts.firstWhere((s) => s.id == subId))
              : null;
          _quantityInitialized = false; // re-init quantity for new variant
          final step = forProduct?.orderStep ?? 1.0;
          final min = forProduct?.minOrderQty ?? 0.0;
          _quantity = min > 0 ? min : step;
        });
      },
      child: Container(
        width: 80,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? Colors.green[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF164431) : Colors.grey[300]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 36,
                width: 36,
                child: imgUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imgUrl.startsWith('http') ? imgUrl : '${ApiService.baseUrl}$imgUrl',
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(Icons.image, size: 18, color: Colors.grey),
                      )
                    : const Icon(Icons.image, size: 18, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 4),
            Text(name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (cartItem != null)
              Text('(${cartItem.quantity})', style: const TextStyle(fontSize: 8, color: Color(0xFF164431), fontWeight: FontWeight.bold)),
            if (selected)
              const Icon(Icons.check, size: 12, color: Color(0xFF164431)),
          ],
        ),
      ),
    );
  }

  Future<void> _addToCart(Product product, CartProvider cart, CartItem? cartItem) async {
    setState(() => _adding = true);
    if (cartItem != null) {
      await cart.updateQuantity(product.id, cartItem.quantity + _quantity, subProductId: _selectedSub?.id);
    } else {
      await cart.addToBackend(product, quantity: _quantity);
    }
    setState(() => _adding = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} added to cart'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _shareProduct(Product product) {
    final String shareText = 'Check out this fresh ${product.name} on FreshInBasket! Only ₹${product.price.toStringAsFixed(2)}. Download the app now!';
    final box = context.findRenderObject() as RenderBox?;
    final rect = box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;
    SharePlus.instance.share(
      ShareParams(
        text: shareText,
        sharePositionOrigin: rect,
      ),
    );
  }

  /// Format a double quantity nicely: 1.0 → "1", 0.25 → "0.25", 1.5 → "1.5"
  String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) return qty.toInt().toString();
    // Remove unnecessary trailing zeros
    return qty.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Widget _quantityControl(double step, double minQty, String? unit) {
    final canDecrement = (_quantity - step) >= (minQty - 0.0001); // tolerance for float precision
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF164431),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF164431).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              Icons.remove,
              color: canDecrement ? Colors.white : Colors.white38,
              size: 20,
            ),
            onPressed: canDecrement
                ? () => setState(() {
                      _quantity = double.parse((_quantity - step).toStringAsFixed(3));
                    })
                : null,
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            alignment: Alignment.center,
            child: Text(
              '${_formatQty(_quantity)}${unit != null && unit.isNotEmpty ? ' $unit' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 20),
            onPressed: () => setState(() {
              _quantity = double.parse((_quantity + step).toStringAsFixed(3));
            }),
          ),
        ],
      ),
    );
  }
}
