import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'providers/auth_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/wishlist_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/category_products_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/search_screen.dart';
import 'screens/main_shell.dart';
import 'screens/about_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/contact_screen.dart';
import 'screens/my_queries_screen.dart';
import 'screens/wishlist_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/help_center_screen.dart';
import 'screens/order_success_screen.dart';
import 'screens/order_fail_screen.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Top-level background handler — required by firebase_messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// Global navigator key for notification tap navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  // Register background message handler before any messaging setup
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Wire notification navigation callback
  NotificationService.onNavigate = (route, {arguments}) {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      route,
      (r) => false,
      arguments: arguments,
    );
  };

  await NotificationService.instance.initialize();
  await NotificationService.instance.requestPermission();

  runApp(const FreshInBasketApp());
}


class FreshInBasketApp extends StatelessWidget {
  const FreshInBasketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..checkAuth()),
        ChangeNotifierProvider(create: (_) => CartProvider()..loadGuestCart()..initAuthState()),
        ChangeNotifierProvider(create: (_) => WishlistProvider()..initAuthState()),
      ],
      child: MaterialApp(
        title: 'Freshinbasket',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF164431),
            primary: const Color(0xFF164431),
            surface: const Color(0xFFF7F8F5),
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F8F5),
          textTheme: GoogleFonts.outfitTextTheme(),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Color(0xFFF7F8F5),
            foregroundColor: Color(0xFF164431),
          ),
        ),
        initialRoute: '/splash',
        routes: {
          '/splash': (context) => const SplashScreen(),
          '/': (context) => const MainShell(),
          '/auth': (context) => const AuthScreen(),
          '/about': (context) => const AboutScreen(),
          '/edit-profile': (context) => const EditProfileScreen(),
          '/contact': (context) => const ContactScreen(),
          '/my-queries': (context) => const MyQueriesScreen(),
          '/wishlist': (context) => const WishlistScreen(),
          '/cart': (context) => const CartScreen(),
          '/checkout': (context) => const CheckoutScreen(),
          '/help-center': (context) => const HelpCenterScreen(),
          '/order-success': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            return OrderSuccessScreen(
              orderType: args?['orderType'] ?? 'COD',
              orderNumber: args?['orderNumber'] ?? '',
              deliverySlot: args?['deliverySlot'] ?? '',
            );
          },
          '/order-fail': (context) {
            final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
            return OrderFailScreen(reason: args?['reason']);
          },
        },
        onGenerateRoute: (settings) {
          final uri = Uri.parse(settings.name ?? '');
          if (uri.pathSegments.length == 1 && uri.pathSegments[0] == 'main') {
            final tab = settings.arguments is int ? settings.arguments as int : 0;
            return MaterialPageRoute(
              builder: (_) => MainShell(initialTab: tab),
              settings: settings,
            );
          }
          if (uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'category') {
            return MaterialPageRoute(
              builder: (_) =>
                  CategoryProductsScreen(slug: uri.pathSegments[1]),
              settings: settings,
            );
          }
          if (uri.pathSegments.length == 2 &&
              uri.pathSegments[0] == 'product') {
            final id = int.tryParse(uri.pathSegments[1]) ?? 0;
            return MaterialPageRoute(
              builder: (_) => ProductDetailScreen(productId: id),
              settings: settings,
            );
          }
          if (uri.pathSegments.length == 1 &&
              uri.pathSegments[0] == 'search') {
            return MaterialPageRoute(
              builder: (_) =>
                  SearchScreen(query: settings.arguments as String? ?? ''),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (_) => const MainShell(),
            settings: settings,
          );
        },
      ),
    );
  }
}
