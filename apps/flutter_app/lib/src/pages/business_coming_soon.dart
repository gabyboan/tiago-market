import 'package:flutter/material.dart';
import 'package:tiago_market_app/auth/auth_account_button.dart';
import 'package:tiago_market_app/src/navigation/app_routes.dart';

class BusinessComingSoonPage extends StatelessWidget {
  const BusinessComingSoonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiago Market Negocios'),
        actions: const [AuthAccountButton()],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  size: 82,
                  color: Color(0xFF006C51),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Estamos preparando tu espacio de negocio.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Próximamente vas a poder publicar productos, precios y ofertas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 26),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await GoogleAuthService.setRole('buyer');
                      if (!context.mounted) return;
                      Navigator.of(context)
                          .pushReplacementNamed(AppRoutes.search);
                    } catch (_) {
                      // Ignore errors: auth gate will handle current role state.
                    }
                  },
                  icon: const Icon(Icons.shopping_cart_checkout_rounded),
                  label: const Text('Volver al modo comprador'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
