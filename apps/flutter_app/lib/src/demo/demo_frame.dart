import 'package:flutter/material.dart';

class DemoFrame extends StatelessWidget {
  const DemoFrame({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Material(
            color: const Color(0xFFFFF1CB),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.science_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Demo · datos ficticios · sin compras reales',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF493B1B),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      );
}

class DemoInfoPage extends StatelessWidget {
  const DemoInfoPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Acerca de la demo')),
        body: const SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Probá Tiago Market',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              SizedBox(height: 16),
              Text('Buscá leche, arroz, huevo o café; compará dos comercios, '
                  'guardá favoritos y armá una lista de compras.'),
              SizedBox(height: 16),
              Text('Todos los comercios, precios y disponibilidades de esta '
                  'demo son ficticios. No corresponden a ofertas reales.'),
              SizedBox(height: 16),
              Text('La demo no inicia sesión, consulta producción, pide '
                  'ubicación ni crea pedidos. La lista vive en memoria y se '
                  'borra al recargar. Los favoritos y búsquedas se guardan '
                  'solamente en este navegador.'),
            ],
          ),
        ),
      );
}
