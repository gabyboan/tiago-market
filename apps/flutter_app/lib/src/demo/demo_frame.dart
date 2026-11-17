import 'package:flutter/material.dart';

const demoAppVersion = String.fromEnvironment(
  'DEMO_APP_VERSION',
  defaultValue: 'desarrollo',
);
const _demoBuiltAt = String.fromEnvironment('DEMO_BUILT_AT');

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
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Probá Tiago Market',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text('Versión de la app: $demoAppVersion'),
              if (DateTime.tryParse(_demoBuiltAt) case final builtAt?)
                Text('Compilada: ${_formatDate(builtAt.toLocal())}'),
              const SizedBox(height: 16),
              const Text(
                'Recorré la bienvenida, buscá leche, arroz, huevo o café; '
                'compará dos comercios, guardá favoritos y armá una lista de compras. '
                'Desde la lista podés probar la selección de tienda, envío y '
                'método de pago y revisar un borrador con datos ficticios.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Los precios y disponibilidades de esta demo son ficticios. '
                'Las imágenes y los logos identifican productos y comercios; '
                'no corresponden a ofertas reales ni implican afiliación.',
              ),
              const SizedBox(height: 16),
              const Text(
                'La demo no inicia sesión, consulta producción, pide '
                'ubicación ni crea pedidos. La lista vive en memoria y se '
                'borra al recargar. Los favoritos y búsquedas se guardan '
                'solamente en este navegador. El domicilio de ejemplo es '
                'de solo lectura y el borrador se descarta al salir.',
              ),
            ],
          ),
        ),
      );

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
