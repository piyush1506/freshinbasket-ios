import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'main_shell.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F5),
      appBar: AppBar(
        title: const Text('My Basket',
            style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF222222))),
        backgroundColor: const Color(0xFFF7F8F5),
        elevation: 0,
        centerTitle: true,
        actions: [
          if (!cart.isCartEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFB14E3F)),
              onPressed: () => _showClearCartDialog(context, cart),
            ),
        ],
      ),
      body: cart.isCartEmpty
          ? _buildEmptyState(context)
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 110),
                  children: [
                    ...cart.items.map((item) => _CartItemCard(item: item)),
                    const SizedBox(height: 16),
                    _buildSummary(cart),
                  ],
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildCheckoutBar(context, cart),
                ),
              ],
            ),
    );
  }

  void _showClearCartDialog(BuildContext context, CartProvider cart) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Color(0xFFB14E3F)),
            SizedBox(width: 8),
            Text('Clear Basket?'),
          ],
        ),
        content: const Text('Are you sure you want to remove all items from your basket?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              cart.clearBackendCart();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB14E3F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFFE8ECE9),
                shape: BoxShape.circle,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: Image.asset(
                  'images/appicon.jpg',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your basket is empty',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF222222)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Fill your basket with fresh, organic fruits and vegetables straight from our farms.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF888888), height: 1.4),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: ElevatedButton.icon(
                onPressed: () {
                  MainShell.switchTab(context, 1);
                },
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Start Shopping', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF164431),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(CartProvider cart) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order Summary',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFF222222)),
          ),
          const SizedBox(height: 16),
          _summaryRow('Item Subtotal', '₹${cart.subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 12),
          _summaryRow(
            'Delivery Fee',
            cart.deliveryCharge == 0
                ? 'FREE'
                : '₹${cart.deliveryCharge.toStringAsFixed(0)}',
            valueColor: cart.deliveryCharge == 0 ? const Color(0xFF2E7D32) : null,
            isDelivery: true,
          ),
          if (cart.subtotal > 0) ...[
            const SizedBox(height: 12),
            if (cart.deliveryCharge > 0) ...[
              Row(
                children: [
                  const Icon(Icons.delivery_dining_outlined, color: Color(0xFFE5A93C), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add ₹${(cart.settings.freeDeliveryThreshold - cart.subtotal).toStringAsFixed(0)} more for FREE Delivery',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (cart.subtotal / cart.settings.freeDeliveryThreshold).clamp(0.0, 1.0),
                  backgroundColor: const Color(0xFFF1F5F2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE5A93C)),
                  minHeight: 6,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your order qualifies for FREE Delivery! 🎉',
                        style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
          const Divider(height: 28, color: Color(0xFFEEF0EC)),
          _summaryRow(
            'Total Amount',
            '₹${cart.grandTotal.toStringAsFixed(0)}',
            bold: true,
            valueColor: const Color(0xFF164431),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool bold = false, Color? valueColor, bool isDelivery = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            fontSize: bold ? 16 : 14,
            color: bold ? const Color(0xFF222222) : const Color(0xFF666666),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w800 : (isDelivery ? FontWeight.w600 : FontWeight.w500),
            fontSize: bold ? 18 : 14,
            color: valueColor ?? (bold ? const Color(0xFF222222) : const Color(0xFF222222)),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckoutBar(BuildContext context, CartProvider cart) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Grand Total',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${cart.grandTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFF164431),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: _CheckoutButton(cart: cart),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final dynamic item;

  const _CartItemCard({required this.item});

  Widget _buildSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 96,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0EC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 90,
            decoration: const BoxDecoration(
              color: Color(0xFFF5F5F5),
              borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(height: 14, width: 120, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(4))),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(height: 24, width: 80, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(12))),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(height: 14, width: 40, decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(4))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (item.image == null) {
      return _buildContent(context, null);
    }
    return CachedNetworkImage(
      imageUrl: item.image.startsWith('http')
          ? item.image
          : '${ApiService.baseUrl}${item.image}',
      imageBuilder: (context, imageProvider) => _buildContent(context, imageProvider),
      placeholder: (context, url) => _buildSkeleton(),
      errorWidget: (context, url, error) => _buildContent(context, null),
    );
  }

  Widget _buildContent(BuildContext context, ImageProvider? imageProvider) {
    final cart = context.read<CartProvider>();
    final isOrganic = item.name.toLowerCase().contains('organic');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF0EC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 90,
                color: const Color(0xFFF7F8F6),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: imageProvider != null
                            ? Image(image: imageProvider, fit: BoxFit.contain)
                            : const Icon(Icons.image, color: Colors.grey),
                      ),
                    ),
                    if (isOrganic)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ORGANIC',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF222222),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),

                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      _qtyBtn(Icons.remove, () {
                                        cart.updateQuantity(
                                          item.productId,
                                          item.quantity - item.orderStep,
                                        );
                                      }),
                                      Container(
                                        constraints: const BoxConstraints(minWidth: 32),
                                        alignment: Alignment.center,
                                        child: Text(
                                          item.quantity.truncateToDouble() == item.quantity
                                              ? item.quantity.toInt().toString()
                                              : item.quantity.toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF164431),
                                          ),
                                        ),
                                      ),
                                      _qtyBtn(Icons.add, () {
                                        cart.updateQuantity(
                                          item.productId,
                                          item.quantity + item.orderStep,
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.unit ?? '1 unit',
                                    style: const TextStyle(
                                      color: Color(0xFF666666),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 12, left: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₹${item.totalPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Color(0xFF164431),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                width: 1,
                color: const Color(0xFFEEF0EC),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => cart.removeFromBackend(item.productId),
                  child: Container(
                    width: 48,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFB14E3F),
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 16, color: const Color(0xFF164431)),
        ),
      ),
    );
  }
}

class _CheckoutButton extends StatefulWidget {
  final CartProvider cart;
  const _CheckoutButton({required this.cart});
  @override
  State<_CheckoutButton> createState() => _CheckoutButtonState();
}

class _CheckoutButtonState extends State<_CheckoutButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isLoading
          ? null
          : () async {
              final auth = context.read<AuthProvider>();
              if (!auth.isLoggedIn) {
                Navigator.pushNamed(context, '/auth');
                return;
              }
              setState(() => _isLoading = true);
              try {
                // 1. Explicitly validate stock for all items concurrently
                final validations = await Future.wait(
                  widget.cart.items.map((item) async {
                    final product = await ApiService.fetchProduct(item.productId);
                    return {'item': item, 'product': product};
                  }),
                );

                for (var v in validations) {
                  final item = v['item'] as dynamic; // CartItem
                  final product = v['product'] as dynamic; // Product
                  
                  if (item.subProductId != null) {
                    final sub = product.subproducts.firstWhere(
                      (s) => s.id == item.subProductId,
                      orElse: () => throw Exception('${item.name} is no longer available'),
                    );
                    if (item.quantity > sub.stock) {
                      throw Exception('Only ${sub.stock} ${sub.unit ?? item.unit ?? ''} available for ${item.name}');
                    }
                  } else {
                    if (item.quantity > product.stock) {
                      throw Exception('Only ${product.stock} ${product.unit ?? item.unit ?? ''} available for ${item.name}');
                    }
                  }
                }

                // 2. Clear and merge cart
                await ApiService.clearCart();
                await ApiService.mergeCart(
                    widget.cart.items.map((i) => i.toJson()).toList());
                    
                if (mounted) {
                  Navigator.pushNamed(context, '/checkout');
                }
              } catch (e) {
                if (mounted) {
                  final msg = e
                      .toString()
                      .replaceFirst('Exception: ', '')
                      .replaceFirst('error: ', '')
                      .trim();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF164431),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2))
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Checkout',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
    );
  }
}
