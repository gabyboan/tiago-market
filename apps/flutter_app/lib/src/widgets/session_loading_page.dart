import 'package:flutter/material.dart';

class SessionLoadingPage extends StatelessWidget {
  const SessionLoadingPage({required this.returningUser, super.key});

  final bool returningUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 38,
              backgroundColor: Color(0xFF006C51),
              foregroundColor: Colors.white,
              child: Icon(Icons.shopping_basket_rounded, size: 38),
            ),
            const SizedBox(height: 22),
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              returningUser
                  ? 'Ingresando con tu cuenta de Google...'
                  : 'Comprobando tu sesión...',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
