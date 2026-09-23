import 'package:flutter/material.dart';

class LegalInfoPage extends StatelessWidget {
  const LegalInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aviso legal y privacidad'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [
              Text(
                'Aviso de privacidad',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 12),
              Text(
                'Tiago Market es una aplicación de comparación de precios que facilita la búsqueda de productos y el seguimiento de listas de compras. Esta aplicación no es un establecimiento comercial y no vende productos directamente.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                'Tratamiento de datos personales',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Cuando usas la aplicación, podemos procesar tu correo electrónico y datos de sesión para identificarte si inicias sesión con Google. Tu ubicación solo se recoge cuando activas la búsqueda de tiendas cercanas para calcular distancias; no la compartimos con terceros sin tu consentimiento explícito.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Las versiones release de Android envían informes de fallos a Firebase Crashlytics. Estos diagnósticos incluyen información técnica del dispositivo, la versión de la app y la traza del error para investigar problemas de estabilidad.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Tiago Market cumple con la Ley Federal de Protección de Datos Personales en Posesión de los Particulares de México. Tus datos se usan únicamente para la prestación del servicio y para mejorar tu experiencia dentro de la app.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                'Consentimiento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Al usar esta aplicación, aceptas que tus datos sean tratados conforme a este aviso de privacidad. Si deseas revocar tu consentimiento, cierra tu sesión y elimina la aplicación de tu dispositivo.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                'Términos de uso',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'La información de precios y productos se obtiene de fuentes públicas, observaciones de tiendas y datos de terceros. Tiago Market no garantiza que la información sea completa, precisa o actualizada en todo momento.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Esta app es una herramienta informativa, no una oferta contractual. La disponibilidad de productos, precios y promociones depende de cada tienda, y puede cambiar sin previo aviso.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                'Descargo de responsabilidad',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Tiago Market no se hace responsable por daños, pérdidas o gastos derivados del uso de la información presentada en la aplicación. Las decisiones de compra son responsabilidad del usuario.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Las comparaciones de precios son estimaciones basadas en datos disponibles. El costo real al momento de la compra puede variar según cambios de precio, disponibilidad, ubicación o condiciones de la tienda.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                'Uso de la aplicación',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'La app está diseñada para ayudarte a comparar y planear tus compras. No reemplaza la verificación directa en la tienda. Siempre revisa los precios finales y la información en el punto de venta antes de comprar.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 16),
              Text(
                'Contacto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Si tienes dudas sobre privacidad o los términos de uso, revisa la configuración de tu dispositivo o contacto al desarrollador de la aplicación a través de los canales que se indiquen en la tienda de aplicaciones.',
                style: TextStyle(height: 1.5),
              ),
              SizedBox(height: 24),
              Text(
                'Este aviso no constituye asesoría legal; es una declaración de intenciones y de prácticas generales aplicada a la operación de la aplicación en México.',
                style: TextStyle(height: 1.5, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
