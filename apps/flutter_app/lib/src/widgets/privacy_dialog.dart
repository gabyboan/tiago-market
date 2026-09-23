import 'package:flutter/material.dart';

class PrivacyDialog extends StatelessWidget {
  const PrivacyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Privacidad en Tiago Market'),
      content: const SingleChildScrollView(
        child: Text(
          'Usamos tu cuenta de Google para identificar tu sesión. '
          'Tu ubicación solo se solicita cuando eliges buscar tiendas cercanas '
          'y se envía para calcular distancias. No vendemos tus datos. '
          'En Android, las versiones release envían diagnósticos de fallos a Firebase Crashlytics para mejorar la estabilidad. '
          'Los precios son observaciones de tiendas y pueden cambiar.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}
