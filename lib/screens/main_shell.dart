import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../providers/cart_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/wishlist_provider.dart';
import '../services/api_service.dart';
import '../widgets/floating_cart_button.dart';
import 'home_screen.dart';
import 'category_screen.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  final int initialTab;

  const MainShell({super.key, this.initialTab = 0});

  static void switchTab(BuildContext context, int index) {
    context.findAncestorStateOfType<MainShellState>()?.switchTab(index);
  }

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  late int _currentTab;
  bool _isBottomNavVisible = true;

  final _pages = const [
    HomeScreen(),
    CategoryScreen(),
    CartScreen(),
    OrdersScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    ApiService.onUnauthorized = () {
      if (mounted) {
        context.read<AuthProvider>().logout();
        context.read<CartProvider>().logout();
        context.read<WishlistProvider>().logout();
      }
    };
  }

  void switchTab(int index) {
    if (index != _currentTab) setState(() => _currentTab = index);
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = context.watch<CartProvider>().itemCount;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const navBarHeight = 80.0;

    return Scaffold(
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction == ScrollDirection.forward) {
            if (!_isBottomNavVisible) setState(() => _isBottomNavVisible = true);
          } else if (notification.direction == ScrollDirection.reverse) {
            if (_isBottomNavVisible) setState(() => _isBottomNavVisible = false);
          }
          return false;
        },
        child: IndexedStack(
          index: _currentTab,
          children: _pages,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: (_currentTab == 0 || _currentTab == 1)
          ? const FloatingCartButton() 
          : null,
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        height: _isBottomNavVisible ? navBarHeight + bottomPadding : 0.0,
        child: ClipRect(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: NavigationBar(
              selectedIndex: _currentTab,
              onDestinationSelected: switchTab,
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFF164431),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              height: navBarHeight,
              destinations: [
                NavigationDestination(
                  icon: Icon(_currentTab == 0 ? Icons.home : Icons.home_outlined, color: _currentTab == 0 ? Colors.white : null),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(_currentTab == 1 ? Icons.storefront : Icons.storefront_outlined, color: _currentTab == 1 ? Colors.white : null),
                  label: 'Shop',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: itemCount > 0,
                    label: Text(itemCount > 99 ? '99+' : '$itemCount'),
                    child: Icon(_currentTab == 2 ? Icons.shopping_cart : Icons.shopping_cart_outlined, color: _currentTab == 2 ? Colors.white : null),
                  ),
                  label: 'Cart',
                ),
                NavigationDestination(
                  icon: Icon(_currentTab == 3 ? Icons.receipt_long : Icons.receipt_long_outlined, color: _currentTab == 3 ? Colors.white : null),
                  label: 'Orders',
                ),
                NavigationDestination(
                  icon: Icon(_currentTab == 4 ? Icons.person : Icons.person_outline, color: _currentTab == 4 ? Colors.white : null),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
