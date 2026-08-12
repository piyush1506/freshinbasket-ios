import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../providers/cart_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/delivery_slot.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addressCtrl = TextEditingController();
  String _paymentMethod = 'COD';
  bool _processing = false;
  DeliverySlot? _selectedSlot;
  bool _loadingSlots = true;

  final MapController _mapController = MapController();
  LatLng _currentCenter = const LatLng(25.3471, 74.6408);
  bool _mapInteracted = false;

  late Razorpay _razorpay;
  String? _lastCheckoutAddress;
  String? _lastCheckoutLatitude;
  String? _lastCheckoutLongitude;

  // Bhilwara Railway Station coordinates (reference point)
  static const _stationLat = 25.3504;
  static const _stationLng = 74.6368;

  double? _distanceFromStation; // in km
  bool _outOfRange = false;

  static const _green = Color(0xFF164431);
  static const _lightGreen = Color(0xFFF0FDF4);
  static const _bg = Color(0xFFF5F7F5);

  @override
  void initState() {
    super.initState();
    _fetchSlots();
    _getCurrentLocation(isUserClick: false);
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  Future<void> _fetchSlots() async {
    try {
      final slot = await ApiService.fetchCurrentDeliverySlot();
      if (!mounted) return;
      setState(() {
        _selectedSlot = slot;
        _loadingSlots = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSlots = false);
    }
  }

  Future<void> _reverseGeocode(double lat, double lng) async {
    _checkDeliveryRadius(lat, lng);
    try {
      final res = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&addressdetails=1'),
        headers: {'User-Agent': 'Freshinbasket/1.0'},
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['display_name'] != null && mounted) {
          setState(() => _addressCtrl.text = data['display_name']);
        }
      }
    } catch (_) {}
  }

  // Haversine formula — returns distance in km
  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  void _checkDeliveryRadius(double lat, double lng) {
    if (!mounted) return;
    final maxRadius = context.read<CartProvider>().settings.maxDeliveryRadius;
    final dist = _haversine(_stationLat, _stationLng, lat, lng);
    setState(() {
      _distanceFromStation = dist;
      _outOfRange = maxRadius > 0 && dist > maxRadius;
    });
  }

  Future<void> _getCurrentLocation({required bool isUserClick}) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      if (!isUserClick) return;
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Location permissions are denied.')));
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      if (isUserClick && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Location permissions are permanently denied. Please enable them in settings.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (isUserClick && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Location services (GPS) are disabled. Please turn on GPS.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'ENABLE',
              textColor: Colors.white,
              onPressed: () async {
                await Geolocator.openLocationSettings();
              },
            ),
          ),
        );
      }
      return;
    }
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      final newLoc = LatLng(position.latitude, position.longitude);
      _mapController.move(newLoc, 17.0);
      if (mounted) {
        setState(() {
          _currentCenter = newLoc;
          _mapInteracted = true;
        });
      }
      _reverseGeocode(position.latitude, position.longitude);
    } catch (e) {
      if (!mounted) return;
      if (isUserClick) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Could not get location: $e. Try opening settings to check permissions.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'SETTINGS',
              onPressed: () async {
                await Geolocator.openAppSettings();
              },
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _mapController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please enter delivery address'),
          behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _processing = true);
    try {
      final cart = context.read<CartProvider>();
      if (cart.items.isNotEmpty) {
        try {
          await ApiService.clearCart();
          await ApiService.mergeCart(
              cart.items.map((i) => i.toJson()).toList());
        } catch (_) {}
      }
      final fullAddress = _addressCtrl.text.trim();
      final latStr = _mapInteracted ? _currentCenter.latitude.toString() : null;
      final lngStr =
          _mapInteracted ? _currentCenter.longitude.toString() : null;

      Map<String, dynamic>? finalOrderData;
      if (_paymentMethod == 'COD') {
        finalOrderData = await ApiService.createCODOrder(
            deliveryAddress: fullAddress,
            deliveryLatitude: latStr,
            deliveryLongitude: lngStr);
      } else {
        final orderData = await ApiService.createRazorpayOrder();
        if (mounted) {
          setState(() => _processing = false);
          _initRazorpay(orderData, fullAddress, latStr, lngStr);
          return;
        }
      }
      if (mounted) {
        context.read<CartProvider>().clearBackendCart();
        Navigator.pushReplacementNamed(
          context,
          '/order-success',
          arguments: {
            'orderType': _paymentMethod,
            'orderNumber': finalOrderData?['order_number'] ?? '',
            'deliverySlot': finalOrderData?['delivery_slot'] ?? '',
          },
        );
      }
    } catch (e) {
      if (mounted) {
        final cleanMsg = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('error: ', '')
            .trim();
        Navigator.pushReplacementNamed(
          context,
          '/order-fail',
          arguments: {'reason': cleanMsg},
        );
      }
    }
    if (mounted) setState(() => _processing = false);
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() => _processing = true);
    try {
      final finalOrderData = await ApiService.verifyPayment(
        razorpayOrderId: response.orderId ?? '',
        razorpayPaymentId: response.paymentId ?? '',
        razorpaySignature: response.signature ?? '',
        deliveryAddress: _lastCheckoutAddress ?? '',
        deliveryLatitude: _lastCheckoutLatitude,
        deliveryLongitude: _lastCheckoutLongitude,
      );
      if (mounted) {
        context.read<CartProvider>().clearBackendCart();
        Navigator.pushReplacementNamed(
          context,
          '/order-success',
          arguments: {
            'orderType': 'ONLINE',
            'orderNumber': finalOrderData['order_number'] ?? '',
            'deliverySlot': finalOrderData['delivery_slot'] ?? '',
          },
        );
      }
    } catch (e) {
      if (mounted) {
        final cleanMsg = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('error: ', '')
            .trim();
        Navigator.pushReplacementNamed(
          context,
          '/order-fail',
          arguments: {'reason': 'Payment Verification Failed: $cleanMsg'},
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      Navigator.pushReplacementNamed(
        context,
        '/order-fail',
        arguments: {
          'reason': 'Payment Failed: ${response.message ?? "Unknown Error"}'
        },
      );
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('External Wallet: ${response.walletName}'),
          behavior: SnackBarBehavior.floating));
  }

  void _initRazorpay(Map<String, dynamic> orderData, String address,
      String? lat, String? lng) {
    _lastCheckoutAddress = address;
    _lastCheckoutLatitude = lat;
    _lastCheckoutLongitude = lng;
    final user = context.read<AuthProvider>().user;
    final options = {
      'key': orderData['key'],
      'amount': orderData['amount'],
      'name': 'Freshinbasket',
      'order_id': orderData['order_id'],
      'description': 'Payment for Fresh Vegetables/Fruits Order',
      'prefill': {
        'contact': user?.phoneNumber ?? '',
        'email': user?.email ?? '',
        'username': user?.username ?? ''
      },
      'external': {
        'wallets': ['paytm']
      },
    };
    try {
      _razorpay.open(options);
    } catch (e) {
      debugPrint('Error launching Razorpay: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error launching payment gateway: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<AuthProvider>().user;
    if (_addressCtrl.text.isEmpty && user?.address != null) {
      _addressCtrl.text = user!.address!;
    }
  }

  // ─────────────── BUILD ───────────────

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF222222)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Checkout',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111111)),
        ),
      ),
      body: Stack(
        children: [
          // Scrollable content
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
            children: [
              _sectionCard(
                icon: Icons.location_on_rounded,
                title: 'Delivery Location',
                child: Column(
                  children: [
                    // Map
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 280,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _currentCenter,
                                initialZoom: 13.0,
                                onPositionChanged: (position, hasGesture) {
                                  if (hasGesture && position.center != null) {
                                    setState(() {
                                      _currentCenter = position.center!;
                                      _mapInteracted = true;
                                    });
                                  }
                                },
                                onMapEvent: (event) {
                                  if (event is MapEventMoveEnd &&
                                      _mapInteracted) {
                                    _reverseGeocode(_currentCenter.latitude,
                                        _currentCenter.longitude);
                                  }
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.example.freshinbasket',
                                ),
                              ],
                            ),
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 40),
                                child: Icon(Icons.location_pin,
                                    color: Color(0xFFE53935), size: 44),
                              ),
                            ),
                            Positioned(
                              bottom: 10,
                              right: 10,
                              child: GestureDetector(
                                onTap: () =>
                                    _getCurrentLocation(isUserClick: true),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 8)
                                    ],
                                  ),
                                  child: const Icon(Icons.my_location_rounded,
                                      color: _green, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Address field
                    TextFormField(
                      controller: _addressCtrl,
                      maxLines: 3,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF222222)),
                      decoration: InputDecoration(
                        hintText: 'Enter your full delivery address',
                        hintStyle: const TextStyle(
                            color: Color(0xFFAAAAAA), fontSize: 13),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.home_outlined,
                              color: _green, size: 20),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF2F2F2),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _green, width: 1.5)),
                      ),
                    ),

                    // ── Delivery radius warning ──
                    if (_distanceFromStation != null) ...[
                      const SizedBox(height: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _outOfRange
                              ? const Color(0xFFFFF3F3)
                              : const Color(0xFFF2F2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _outOfRange
                                ? const Color(0xFFE53935)
                                : const Color(0xFFDDDDDD),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _outOfRange
                                  ? Icons.location_off_rounded
                                  : Icons.location_on_rounded,
                              color: _outOfRange
                                  ? const Color(0xFFE53935)
                                  : _green,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _outOfRange
                                        ? 'Outside Delivery Zone'
                                        : 'Within Delivery Zone',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: _outOfRange
                                          ? const Color(0xFFE53935)
                                          : _green,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _outOfRange
                                        ? 'We currently do not deliver to this area. Selected location is ${_distanceFromStation!.toStringAsFixed(1)} km away.'
                                        : 'Selected location is ${_distanceFromStation!.toStringAsFixed(1)} km away.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _outOfRange
                                          ? const Color(0xFFC62828)
                                          : const Color(0xFF388E3C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Delivery Slot
              _sectionCard(
                icon: Icons.schedule_rounded,
                title: 'Delivery Slot',
                child: _buildSlotWidget(),
              ),

              const SizedBox(height: 14),

              // Payment Method
              _sectionCard(
                icon: Icons.payment_rounded,
                title: 'Payment Method',
                child: Column(
                  children: [
                    _paymentTile(
                      value: 'COD',
                      title: 'Cash on Delivery',
                      subtitle: 'Pay when your order arrives',
                      icon: Icons.money_rounded,
                    ),
                    const SizedBox(height: 10),
                    _paymentTile(
                      value: 'ONLINE',
                      title: 'Online Payment',
                      subtitle: 'Card / UPI / Net Banking',
                      icon: Icons.credit_card_rounded,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Bill Summary
              _sectionCard(
                icon: Icons.receipt_long_rounded,
                title: 'Bill Summary',
                child: Column(
                  children: [
                    _billRow(
                        'Subtotal', '₹${cart.subtotal.toStringAsFixed(2)}'),
                    const SizedBox(height: 8),
                    _billRow(
                      'Delivery Charge',
                      cart.deliveryCharge == 0
                          ? 'FREE'
                          : '₹${cart.deliveryCharge.toStringAsFixed(2)}',
                      valueColor: cart.deliveryCharge == 0 ? _green : null,
                    ),
                    if (cart.deliveryCharge == 0 && cart.subtotal > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.local_offer_rounded,
                              color: _green, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            'Free delivery on orders above ₹${cart.settings.freeDeliveryThreshold.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: _green,
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: Color(0xFFEEEEEE)),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Amount',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF111111))),
                        Text(
                          '₹${cart.grandTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: _green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Sticky bottom CTA ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  16, 14, 16, 12 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, -4))
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Out of range banner in CTA area
                  if (_outOfRange) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3F3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE53935)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.block_rounded,
                              color: Color(0xFFE53935), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cannot deliver to this location',
                              style: TextStyle(
                                  color: Color(0xFFE53935),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('To Pay',
                          style: TextStyle(
                              color: Color(0xFF888888), fontSize: 12)),
                      Text(
                        '₹${context.watch<CartProvider>().grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: _green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          (_processing || _outOfRange) ? null : _placeOrder,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _outOfRange ? Colors.grey : _green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _outOfRange
                            ? Colors.grey.shade300
                            : _green.withOpacity(0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _processing
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : _outOfRange
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.location_off_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Delivery Not Available',
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                        _paymentMethod == 'COD'
                                            ? Icons.check_circle_rounded
                                            : Icons.lock_rounded,
                                        size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      _paymentMethod == 'COD'
                                          ? 'Place Order'
                                          : 'Pay ₹${context.watch<CartProvider>().grandTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.3),
                                    ),
                                  ],
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section card wrapper ──
  Widget _sectionCard(
      {required IconData icon, required String title, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: _green, size: 16),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111111))),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  // ── Delivery slot widget ──
  Widget _buildSlotWidget() {
    if (_loadingSlots) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_selectedSlot == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
        child: const Text('No delivery slots available',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDDDDD)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _green, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.local_shipping_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('You will receive order in between and before ',
                    style: TextStyle(color: Color(0xFF555555), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(_selectedSlot!.displayLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _green,
                        fontSize: 14)),
              ],
            ),
          ),
          const Icon(Icons.check_circle_rounded, color: _green, size: 20),
        ],
      ),
    );
  }

  // ── Payment tile ──
  Widget _paymentTile(
      {required String value,
      required String title,
      required String subtitle,
      required IconData icon}) {
    final selected = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF2F2F2) : const Color(0xFFF9F9F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? _green : const Color(0xFFE0E0E0),
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? _green : const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  color: selected ? Colors.white : Colors.grey, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: selected ? _green : const Color(0xFF222222))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF888888))),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? _green : const Color(0xFFCCCCCC),
                    width: 2),
                color: selected ? _green : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Bill row ──
  Widget _billRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF666666), fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? const Color(0xFF222222),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
