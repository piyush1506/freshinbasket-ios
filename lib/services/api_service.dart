import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' hide Category;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/category.dart';
import 'package:freshinbasket/models/slide.dart';
import '../models/cart_item.dart';
import '../models/order.dart';
import '../models/store_settings.dart';
import '../models/review.dart';
import '../models/wishlist_item.dart';
import '../models/delivery_slot.dart';
import '../models/contact_query.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static String get baseUrl => dotenv.env['API_URL'] ?? 'https://freshinbasket.com';

  /// Sanitizes an exception message so internal network details (IPs, URLs)
  /// are never exposed to the user.
  static String _sanitize(Object e) {
    if (e is SocketException || e is http.ClientException) {
      return 'Unable to connect to server. Please check your internet connection and try again.';
    }
    final msg = e.toString().replaceFirst('Exception: ', '');
    // Strip any message that leaks a raw URL / IP address
    if (msg.contains(baseUrl) || RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(msg)) {
      return 'Unable to connect to server. Please check your internet connection and try again.';
    }
    return msg;
  }
  static VoidCallback? onUnauthorized;

  static Future<Map<String, String>> _headers({bool multipart = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return {
      if (!multipart) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static dynamic _safeDecode(String body) {
    if (body.trimLeft().startsWith('<')) {
      return null;
    }
    try {
      return json.decode(body);
    } catch (_) {
      return null;
    }
  }

  static Future<dynamic> _request(
    Future<http.Response> Function() sendRequest,
  ) async {
    try {
      var response = await sendRequest();
      if (response.statusCode == 401) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          response = await sendRequest();
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return null;
        final decoded = _safeDecode(response.body);
        if (decoded != null) return decoded;
        throw Exception('Server returned unexpected response. Please try again.');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        onUnauthorized?.call();
      }
      final body = _safeDecode(response.body) ?? <String, dynamic>{};
      throw Exception(_extractError(body) ?? 'Request failed (${response.statusCode})');
    } on SocketException {
      throw Exception('Unable to connect to server. Please check your internet connection and try again.');
    } on http.ClientException {
      throw Exception('Unable to connect to server. Please check your internet connection and try again.');
    }
  }

  static Future<dynamic> _requestFromStream(
    Future<http.StreamedResponse> Function() sendRequest,
  ) async {
    try {
      var streamed = await sendRequest();
      var response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401) {
        final refreshed = await _refreshToken();
        if (refreshed) {
          streamed = await sendRequest();
          response = await http.Response.fromStream(streamed);
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return null;
        final decoded = _safeDecode(response.body);
        if (decoded != null) return decoded;
        throw Exception('Server returned unexpected response. Please try again.');
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        onUnauthorized?.call();
      }
      final body = _safeDecode(response.body) ?? <String, dynamic>{};
      throw Exception(_extractError(body) ?? 'Request failed (${response.statusCode})');
    } on SocketException {
      throw Exception('Unable to connect to server. Please check your internet connection and try again.');
    } on http.ClientException {
      throw Exception('Unable to connect to server. Please check your internet connection and try again.');
    }
  }

  static String? _extractError(Map<String, dynamic> body) {
    if (body.containsKey('detail')) {
      final detail = body['detail'] as String?;
      if (detail != null && detail.contains('token is not valid')) {
        return 'Your session has expired. Please log in again.';
      }
      if (detail != null && detail.contains('Authentication credentials were not provided')) {
        return 'Please log in to continue.';
      }
      return detail;
    }
    if (body.containsKey('message')) return body['message'] as String?;
    if (body.containsKey('non_field_errors')) {
      final v = body['non_field_errors'];
      return v is List ? v.join(', ') : v.toString();
    }
    final messages = <String>[];
    for (final entry in body.entries) {
      final v = entry.value;
      
      // Handle badly serialized Python ErrorDetail strings
      if (v.toString().contains('token_not_valid') || v.toString().contains('Token is expired') || v.toString().contains('ErrorDetail')) {
        return 'Your session has expired. Please log in again.';
      }

      if (v is List && v.isNotEmpty) {
        messages.add('${entry.key}: ${v.join(', ')}');
      } else if (v is String) {
        messages.add('${entry.key}: $v');
      }
    }
    return messages.isNotEmpty ? messages.join('\n') : null;
  }

  static Future<bool> _refreshToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refresh = prefs.getString('refresh_token');
      if (refresh == null) {
        onUnauthorized?.call();
        return false;
      }
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/auth/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'refresh': refresh}),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        await prefs.setString('access_token', data['access']);
        return true;
      }
      // If refresh fails, clear auth data so user can re-login
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_data');
      onUnauthorized?.call();
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Slide>> fetchHomeSlides() async {
    final data = await fetchHome();
    return (data['slides'] as List?)?.map((s) => Slide.fromJson(s)).toList() ?? [];
  }

  static Future<List<Category>> fetchHomeCategories() async {
    final data = await fetchHome();
    return (data['categories'] as List?)?.map((c) => Category.fromJson(c)).toList() ?? [];
  }

  static Future<Map<String, dynamic>> fetchHome() async {
    return await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/home/'),
      headers: await _headers(),
    ));
  }

  static Future<List<Product>> fetchProducts({String? category}) async {
    final uri = Uri.parse('$baseUrl/api/v1/products/').replace(
      queryParameters: category != null ? {'category': category} : null,
    );
    final data = await _request(() async => http.get(uri, headers: await _headers()));
    return (data as List).map((p) => Product.fromJson(p)).toList();
  }

  static Future<Product> fetchProduct(int id) async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/products/$id/'),
      headers: await _headers(),
    ));
    return Product.fromJson(data);
  }

  static Future<List<Product>> searchProducts(String query, {int? limit}) async {
    final uri = Uri.parse('$baseUrl/api/v1/products/search/').replace(
      queryParameters: {
        'q': query,
        if (limit != null) 'limit': limit.toString(),
      },
    );
    final data = await _request(() async => http.get(uri, headers: await _headers()));
    final list = data is List ? data : (data['results'] as List? ?? []);
    return (list).map((p) => Product.fromJson(p)).toList();
  }

  static Future<List<Product>> searchSuggestions(String query) async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/products/search/?q=${Uri.encodeQueryComponent(query)}&suggest=1'),
      headers: await _headers(),
    ));
    final list = data is List ? data : (data['results'] as List? ?? []);
    return (list).map((p) => Product.fromJson(p)).toList();
  }

  static Future<List<Category>> fetchCategories() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/categories/'),
      headers: await _headers(),
    ));
    return (data as List).map((c) => Category.fromJson(c)).toList();
  }

  static Future<Category?> fetchCategory(String slug) async {
    final categories = await fetchCategories();
    try {
      return categories.firstWhere((c) => c.slug == slug);
    } catch (_) {
      return null;
    }
  }

  static Future<StoreSettings> fetchStoreSettings() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/store-info/'),
      headers: await _headers(),
    ));
    return StoreSettings.fromJson(data);
  }

  static Future<List<CartItem>> fetchCart() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/cart/'),
      headers: await _headers(),
    ));
    return (data['items'] as List?)?.map((i) => CartItem.fromJson(i)).toList() ?? [];
  }

  static Future<void> addToCart(int productId, double quantity) async {
    await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/cart/add_item/'),
      headers: await _headers(),
      body: json.encode({'product_id': productId, 'quantity': quantity}),
    ));
  }

  static Future<void> removeFromCart(int productId) async {
    await _request(() async => http.delete(
      Uri.parse('$baseUrl/api/v1/cart/remove_item/'),
      headers: await _headers(),
      body: json.encode({'product_id': productId}),
    ));
  }

  static Future<void> clearCart() async {
    await _request(() async => http.delete(
      Uri.parse('$baseUrl/api/v1/cart/clear/'),
      headers: await _headers(),
    ));
  }

  static Future<void> mergeCart(List<Map<String, dynamic>> items) async {
    await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/cart/merge/'),
      headers: await _headers(),
      body: json.encode({'items': items}),
    ));
  }

  static Future<Map<String, dynamic>> createRazorpayOrder() async {
    return await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/payment/create-order/'),
      headers: await _headers(),
    ));
  }

  static Future<Map<String, dynamic>> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required String deliveryAddress,
    String? deliveryLatitude,
    String? deliveryLongitude,
  }) async {
    return await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/payment/verify/'),
      headers: await _headers(),
      body: json.encode({
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
        'delivery_address': deliveryAddress,
        if (deliveryLatitude != null) 'delivery_latitude': deliveryLatitude,
        if (deliveryLongitude != null) 'delivery_longitude': deliveryLongitude,
      }),
    ));
  }

  static Future<Map<String, dynamic>> createCODOrder({
    required String deliveryAddress,
    String? deliveryLatitude,
    String? deliveryLongitude,
  }) async {
    return await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/payment/cod/'),
      headers: await _headers(),
      body: json.encode({
        'delivery_address': deliveryAddress,
        if (deliveryLatitude != null) 'delivery_latitude': deliveryLatitude,
        if (deliveryLongitude != null) 'delivery_longitude': deliveryLongitude,
      }),
    ));
  }

  static Future<List<Order>> fetchOrders() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/orders/'),
      headers: await _headers(),
    ));
    return (data as List).map((o) => Order.fromJson(o)).toList();
  }

  static Future<void> cancelOrder(int orderId) async {
    await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/orders/$orderId/cancel/'),
      headers: await _headers(),
    ));
  }

  static Future<void> updateOrderAddress({
    required int orderId,
    required String deliveryAddress,
    String? deliveryLatitude,
    String? deliveryLongitude,
  }) async {
    await _request(() async => http.patch(
      Uri.parse('$baseUrl/api/v1/orders/$orderId/'),
      headers: await _headers(),
      body: json.encode({
        'delivery_address': deliveryAddress,
        if (deliveryLatitude != null) 'delivery_latitude': deliveryLatitude,
        if (deliveryLongitude != null) 'delivery_longitude': deliveryLongitude,
      }),
    ));
  }

  static Future<List<DeliverySlot>> fetchDeliverySlots() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/delivery-slots/'),
      headers: await _headers(),
    ));
    return (data as List).map((s) => DeliverySlot.fromJson(s)).toList();
  }

  static Future<DeliverySlot?> fetchCurrentDeliverySlot() async {
    try {
      final data = await _request(() async => http.get(
        Uri.parse('$baseUrl/api/v1/delivery-slots/current/'),
        headers: await _headers(),
      ));
      return DeliverySlot.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> updateProfile(Map<String, dynamic> data) async {
    await _request(() async => http.patch(
      Uri.parse('$baseUrl/api/v1/users/me/'),
      headers: await _headers(),
      body: json.encode(data),
    ));
  }

  static Future<List<dynamic>> fetchContactQueries() async {
    return await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/contact/'),
      headers: await _headers(),
    )) as List;
  }

  static Future<List<ContactQuery>> fetchContactQueriesModel() async {
    final data = await fetchContactQueries();
    return data.map((q) => ContactQuery.fromJson(q)).toList();
  }

  static Future<void> submitContact({
    required String name,
    required String email,
    required String message,
  }) async {
    await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/contact/'),
      headers: await _headers(),
      body: json.encode({'name': name, 'email': email, 'message': message}),
    ));
  }

  // ─── Wishlist ──────────────────────────────────────────────

  static Future<List<WishlistItem>> fetchWishlist() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/wishlist/'),
      headers: await _headers(),
    ));
    return (data as List).map((i) => WishlistItem.fromJson(i)).toList();
  }

  static Future<void> addToWishlist(int productId) async {
    await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/wishlist/'),
      headers: await _headers(),
      body: json.encode({'product': productId}),
    ));
  }

  static Future<void> removeFromWishlist(int productId) async {
    await _request(() async => http.delete(
      Uri.parse('$baseUrl/api/v1/wishlist/remove/'),
      headers: await _headers(),
      body: json.encode({'product_id': productId}),
    ));
  }

  static Future<List<int>> fetchWishlistIds() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/wishlist/ids/'),
      headers: await _headers(),
    ));
    return (data as List).cast<int>();
  }

  // ─── Reviews ───────────────────────────────────────────────

  static Future<List<Review>> fetchReviews() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/reviews/'),
      headers: await _headers(),
    ));
    return (data as List).map((r) => Review.fromJson(r)).toList();
  }

  static Future<Review> createReview({
    required int orderId,
    required int rating,
    String? comment,
  }) async {
    final data = await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/reviews/'),
      headers: await _headers(),
      body: json.encode({
        'order': orderId,
        'rating': rating,
        if (comment != null) 'comment': comment,
      }),
    ));
    return Review.fromJson(data);
  }

  // ─── Image Upload ──────────────────────────────────────────

  static Future<String> uploadImage(File file) async {
    final headers = await _headers(multipart: true);
    final data = await _requestFromStream(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/v1/upload/'),
      );
      request.headers.addAll(headers);
      
      final ext = file.path.split('.').last.toLowerCase();
      String mimeType = 'image/jpeg';
      if (ext == 'png') {
        mimeType = 'image/png';
      } else if (ext == 'webp') {
        mimeType = 'image/webp';
      } else if (ext == 'gif') {
        mimeType = 'image/gif';
      }
      
      request.files.add(await http.MultipartFile.fromPath(
        'image',
        file.path,
        contentType: MediaType.parse(mimeType),
      ));
      return request.send();
    });
    return data['secure_url'] as String;
  }

  static Future<String> uploadAvatar(File file) async {
    final headers = await _headers(multipart: true);
    final data = await _requestFromStream(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/v1/users/avatar/'),
      );
      request.headers.addAll(headers);
      
      final ext = file.path.split('.').last.toLowerCase();
      String mimeType = 'image/jpeg';
      if (ext == 'png') {
        mimeType = 'image/png';
      } else if (ext == 'webp') {
        mimeType = 'image/webp';
      } else if (ext == 'gif') {
        mimeType = 'image/gif';
      }
      
      request.files.add(await http.MultipartFile.fromPath(
        'avatar',
        file.path,
        contentType: MediaType.parse(mimeType),
      ));
      return request.send();
    });
    return data['avatar'] as String;
  }

  // ─── Slides ─────────────────────────────────────────────────

  static Future<List<Slide>> fetchSlides() async {
    final data = await _request(() async => http.get(
      Uri.parse('$baseUrl/api/v1/slides/'),
      headers: await _headers(),
    ));
    return (data as List).map((s) => Slide.fromJson(s)).toList();
  }

  // ─── FCM Token Registration ──────────────────────────────────────────────

  static Future<void> registerFCMToken(String token) async {
    await _request(() async => http.post(
      Uri.parse('$baseUrl/api/v1/notifications/register-token/'),
      headers: await _headers(),
      body: json.encode({'token': token}),
    ));
  }
}
