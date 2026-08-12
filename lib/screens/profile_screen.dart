import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/wishlist_provider.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _activeOrdersCount = 0;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _fetchUserStats();
  }

  Future<void> _fetchUserStats() async {
    final auth = context.read<AuthProvider>();
    if (auth.user == null) return;
    try {
      final orders = await ApiService.fetchOrders();
      final activeCount = orders.where((o) => o.status != 'DELIVERED' && o.status != 'CANCELLED').length;
      if (mounted) {
        setState(() {
          _activeOrdersCount = activeCount;
          _loadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingStats = false);
      }
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      await ApiService.uploadAvatar(File(picked.path));
      if (mounted) {
        await context.read<AuthProvider>().fetchProfile();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final cleanMsg = e.toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('error: ', '')
            .trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload: $cleanMsg'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F5),
      appBar: AppBar(
        title: const Text('Profile',
            style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF222222))),
        backgroundColor: const Color(0xFFF7F8F5),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Color(0xFF222222)),
            onPressed: () {
              Navigator.pushNamed(context, '/search');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: user == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.account_circle_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Please log in to view your profile', style: TextStyle(fontSize: 16, color: Color(0xFF444444), fontWeight: FontWeight.w500)),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/auth'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF164431),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Log In'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchUserStats,
              color: const Color(0xFF164431),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  children: [
                    // Profile Header
                    Center(
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Stack(
                          children: [
                            Container(
                              height: 100,
                              width: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFE8F5E9),
                                border: Border.all(color: Colors.white, width: 4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                                image: user.avatar != null && user.avatar!.isNotEmpty
                                    ? DecorationImage(
                                        image: CachedNetworkImageProvider(
                                          user.avatar!.startsWith('http')
                                              ? user.avatar!
                                              : '${ApiService.baseUrl}${user.avatar}',
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: user.avatar == null || user.avatar!.isEmpty
                                  ? Center(
                                      child: Text(
                                        (user.username.isNotEmpty ? user.username[0] : '?').toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF164431),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF164431),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Name and Badge
                    Text(
                      user.username.isEmpty ? 'Customer' : user.username,
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222222)),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEBEBEB),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stars, size: 14, color: Color(0xFF164431)),
                          SizedBox(width: 4),
                          Text(
                            'Verified Member',
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF444444),
                                fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Stats Row (Active Orders)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _loadingStats ? '...' : '$_activeOrdersCount',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF164431)),
                          ),
                          const SizedBox(height: 4),
                          const Text('Active Orders',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF666666))),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Settings Label
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Settings & Security',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF222222)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Settings List
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                        children: [
                          _buildSettingItem(Icons.person_outline, 'Personal Information'),
                          const Divider(height: 1, indent: 56),
                          _buildSettingItem(Icons.notifications_none_outlined, 'Notifications'),
                          const Divider(height: 1, indent: 56),
                          _buildSettingItem(Icons.favorite_outline, 'My Wishlist'),
                          const Divider(height: 1, indent: 56),
                          _buildSettingItem(Icons.help_outline, 'Help Center'),
                        ],
                      ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          context.read<CartProvider>().logout();
                          context.read<WishlistProvider>().logout();
                          await auth.logout();
                          if (context.mounted) {
                            Navigator.pushReplacementNamed(context, '/auth');
                          }
                        },
                        icon: const Icon(Icons.logout, color: Color(0xFFB14E3F)),
                        label: const Text('Log Out',
                            style: TextStyle(
                                color: Color(0xFFB14E3F),
                                fontWeight: FontWeight.w600,
                                fontSize: 16)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: Color(0xFFB14E3F)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'Freshinbasket v2.4.0 • Made with Wholesomeness',
                      style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSettingItem(IconData icon, String title) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFEBEBEB),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF222222), size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF222222),
              fontWeight: FontWeight.w400)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFAAAAAA)),
      onTap: () async {
        if (title == 'Personal Information') {
          await Navigator.pushNamed(context, '/edit-profile');
          _fetchUserStats(); // Re-fetch stats/name on return
        } else if (title == 'My Wishlist') {
          Navigator.pushNamed(context, '/wishlist');
        } else if (title == 'Help Center') {
          Navigator.pushNamed(context, '/help-center');
        }
      },
    );
  }
}
