import 'package:flutter/material.dart';
import 'package:tiago_market_app/auth/auth_account_button.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/navigation/app_routes.dart';

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  void _continueAsGuest(BuildContext context) {
    Navigator.of(context).pushReplacementNamed(AppRoutes.search);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(splashFactory: InkRipple.splashFactory),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CircleAvatar(
                        radius: 42,
                        backgroundColor: Color(0xFF006C51),
                        foregroundColor: Colors.white,
                        child: Icon(Icons.shopping_basket_rounded, size: 42),
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Tu compra merece\nun mejor precio.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 34,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tiago Market compara precios cercanos para ayudarte a ahorrar tiempo y dinero.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 30),
                      if (authEnabled)
                        const GoogleSignInButton(expanded: true)
                      else
                        const FilledButton(
                          onPressed: null,
                          child: Text('Configura Supabase para iniciar sesión'),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _continueAsGuest(context),
                        icon: const Icon(Icons.person_outline_rounded),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Continuar sin cuenta'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        authEnabled
                            ? 'Puedes comparar como invitado o iniciar sesión con Google para guardar tu experiencia.'
                            : 'Modo invitado activo. Configura Supabase para habilitar cuentas.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pushNamed(
                              AppRoutes.legalInfo,
                            ),
                            child: const Text('Aviso legal'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pushNamed(
                              AppRoutes.legalInfo,
                            ),
                            child: const Text('Política de privacidad'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
