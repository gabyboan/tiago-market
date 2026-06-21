import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tiago_market_app/auth/auth_account_button.dart';
import 'package:tiago_market_app/src/navigation/app_routes.dart';

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key, required this.user});

  final User user;

  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage> {
  bool _loading = false;
  String? _error;

  Future<void> _selectRole(String role) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await GoogleAuthService.setRole(role);
      if (!mounted) return;
      if (role == 'buyer') {
        Navigator.of(context).pushReplacementNamed(AppRoutes.search);
      } else {
        Navigator.of(context).pushReplacementNamed(AppRoutes.sellerComingSoon);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.user.userMetadata ?? const <String, dynamic>{};
    final name = metadata['full_name'] as String? ??
        metadata['name'] as String? ??
        widget.user.email ??
        'Hola';
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoutes.legalInfo,
            ),
            tooltip: 'Privacidad',
            icon: const Icon(Icons.privacy_tip_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : GoogleAuthService.signOut,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hola, $name',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '¿Cómo querés usar Tiago Market?',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 28),
                  _RoleCard(
                    icon: Icons.shopping_cart_checkout_rounded,
                    title: 'Quiero comprar',
                    description:
                        'Compará precios y encontrá opciones cercanas.',
                    onTap: _loading ? null : () => _selectRole('buyer'),
                  ),
                  const SizedBox(height: 14),
                  _RoleCard(
                    icon: Icons.storefront_rounded,
                    title: 'Tengo un negocio',
                    description:
                        'Prepará tu perfil para publicar precios y ofertas.',
                    onTap: _loading ? null : () => _selectRole('seller'),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(radius: 28, child: Icon(icon)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
