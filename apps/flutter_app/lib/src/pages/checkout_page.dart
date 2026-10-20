import 'package:flutter/material.dart';
import 'package:tiago_market_app/src/models/checkout.dart';
import 'package:tiago_market_app/src/models/models.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({required this.items, super.key});

  final List<ShoppingItem> items;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final name in [
      'name',
      'phone',
      'street',
      'neighborhood',
      'city',
      'state',
      'zip',
      'notes',
    ])
      name: TextEditingController(),
  };
  late final _baskets = buildCheckoutBaskets(widget.items);
  CheckoutBasket? _basket;
  PaymentMethod _payment = PaymentMethod.card;
  CheckoutDraft? _draft;

  @override
  void initState() {
    super.initState();
    for (final basket in _baskets) {
      if (basket.isComplete) {
        _basket = basket;
        break;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(String name) => _fields[name]!.text.trim();
  String _money(int amount) => '\$${(amount / 100).toStringAsFixed(2)} MXN';

  void _review() {
    if (!_formKey.currentState!.validate() || _basket == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _draft = CheckoutDraft(
        basket: _basket!,
        deliveryMethod: DeliveryMethod.homeDelivery,
        paymentMethod: _payment,
        contact: DeliveryContact(
          fullName: _value('name'),
          phone: _value('phone'),
          street: _value('street'),
          neighborhood: _value('neighborhood'),
          city: _value('city'),
          state: _value('state'),
          postalCode: _value('zip'),
          instructions: _value('notes'),
        ),
      );
    });
  }

  Widget _field(
    String name,
    String label, {
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String)? validate,
    bool required = true,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: _fields[name],
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          keyboardType: keyboard,
          maxLines: maxLines,
          maxLength: name == 'notes' ? 300 : 160,
          buildCounter: (context,
                  {required currentLength, required isFocused, maxLength}) =>
              null,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) return 'Completa este campo';
            return validate?.call(text);
          },
        ),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _option<T>(
      {required T value,
      required T selected,
      required String title,
      required String subtitle,
      required IconData icon,
      required ValueChanged<T> onSelect}) {
    final active = value == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: active
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_off),
          selected: active,
          onTap: () => onSelect(value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(title: const Text('Envío y métodos de pago')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: draft != null
              ? _reviewBody(draft)
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Prepara tu compra',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        const Text(
                            'Configura la entrega y tu forma de pago. Por ahora puedes revisar un borrador; las compras todavía no están habilitadas.'),
                        const SizedBox(height: 20),
                        _section('1. Tienda y productos', [
                          if (_baskets.isEmpty)
                            const Text(
                                'No hay precios disponibles en MXN para preparar esta compra.'),
                          for (final basket in _baskets)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(_basket == basket
                                  ? Icons.check_circle
                                  : Icons.storefront_outlined),
                              title: Text(basket.label),
                              subtitle: Text(
                                  '${basket.lines.length} de ${basket.expectedItems} productos · ${_money(basket.subtotalMinor)}${basket.isComplete ? '' : '\nLista incompleta en esta tienda'}'),
                              enabled: basket.isComplete,
                              onTap: basket.isComplete
                                  ? () => setState(() => _basket = basket)
                                  : null,
                            ),
                          if (_basket == null && _baskets.isNotEmpty)
                            const Text(
                                'Ninguna tienda cubre toda tu lista. Ajusta los productos para preparar una compra en una sola tienda.'),
                          const SizedBox(height: 8),
                          const Text(
                              'Precios de referencia guardados. La tienda deberá confirmar precio, existencias y disponibilidad de entrega.'),
                        ]),
                        _section('2. Envío a domicilio', [
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.local_shipping_outlined),
                            title: Text('Envío a domicilio'),
                            subtitle:
                                Text('Costo, cobertura y fecha por confirmar'),
                          ),
                          const SizedBox(height: 8),
                          _field('name', 'Nombre y apellido'),
                          _field('phone', 'Teléfono de contacto',
                              keyboard: TextInputType.phone,
                              validate: (value) => RegExp(r'^\+?[\d\s()\-]+$')
                                          .hasMatch(value) &&
                                      value
                                              .replaceAll(RegExp(r'\D'), '')
                                              .length >=
                                          10 &&
                                      value
                                              .replaceAll(RegExp(r'\D'), '')
                                              .length <=
                                          15
                                  ? null
                                  : 'Ingresa un teléfono válido (10 a 15 dígitos)'),
                          _field('street', 'Calle, número e interior'),
                          _field('neighborhood', 'Colonia'),
                          _field('city', 'Ciudad o municipio'),
                          _field('state', 'Estado'),
                          _field('zip', 'Código postal de México',
                              keyboard: TextInputType.number,
                              validate: (value) => RegExp(r'^\d{5}$')
                                      .hasMatch(value)
                                  ? null
                                  : 'Ingresa los 5 dígitos del código postal'),
                          _field('notes', 'Indicaciones (opcional)',
                              maxLines: 3, required: false),
                        ]),
                        _section('3. Método de pago', [
                          _option(
                              value: PaymentMethod.card,
                              selected: _payment,
                              title: 'Tarjeta de crédito o débito',
                              subtitle: 'Pago seguro al habilitar la compra',
                              icon: Icons.credit_card,
                              onSelect: (value) =>
                                  setState(() => _payment = value)),
                          _option(
                              value: PaymentMethod.bankTransfer,
                              selected: _payment,
                              title: 'Transferencia bancaria',
                              subtitle:
                                  'Los datos y la referencia se emitirán al confirmar',
                              icon: Icons.account_balance_outlined,
                              onSelect: (value) =>
                                  setState(() => _payment = value)),
                          _option(
                              value: PaymentMethod.cashOnDelivery,
                              selected: _payment,
                              title: 'Efectivo al recibir',
                              subtitle: 'Sujeto a aceptación de la tienda',
                              icon: Icons.payments_outlined,
                              onSelect: (value) =>
                                  setState(() => _payment = value)),
                          const Text(
                              'La disponibilidad de cada método se confirmará al habilitar las compras. No ingreses datos de tarjetas en las indicaciones.'),
                        ]),
                        _section('Resumen estimado', [
                          _amountRow(
                              'Productos',
                              _basket == null
                                  ? '—'
                                  : _money(_basket!.subtotalMinor)),
                          _amountRow('Envío', 'Por cotizar'),
                          _amountRow('Total final', 'Por confirmar'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: _basket == null ? null : _review,
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Revisar borrador')),
                        ]),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _amountRow(String label, String amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(label),
              Text(amount, style: const TextStyle(fontWeight: FontWeight.w700))
            ]),
      );

  Widget _reviewBody(CheckoutDraft draft) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.fact_check_outlined,
              size: 48, color: Color(0xFF006C51)),
          const SizedBox(height: 12),
          const Text('Borrador de compra',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          _section(draft.basket.label, [
            for (final line in draft.basket.lines)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(line.offer.productName),
                  subtitle: Text('Cantidad: ${line.quantity}'),
                  trailing: Text(_money(line.subtotalMinor))),
            _amountRow('Subtotal estimado', _money(draft.basket.subtotalMinor)),
            _amountRow('Envío', 'Por cotizar'),
            _amountRow('Total final', 'Por confirmar'),
          ]),
          _section('Entrega y contacto', [
            const Text('Envío a domicilio'),
            Text(draft.contact.fullName),
            Text(draft.contact.phone),
            Text(draft.contact.street),
            Text(draft.contact.neighborhood),
            Text(
                '${draft.contact.city}, ${draft.contact.state}, CP ${draft.contact.postalCode}, México'),
            if (draft.contact.instructions.isNotEmpty)
              Text(draft.contact.instructions),
          ]),
          _section('Forma de pago elegida', [
            Text(switch (draft.paymentMethod) {
              PaymentMethod.card => 'Tarjeta de crédito o débito',
              PaymentMethod.bankTransfer => 'Transferencia bancaria',
              PaymentMethod.cashOnDelivery => 'Efectivo al recibir',
            }),
            const SizedBox(height: 8),
            const Text(
                'Pendiente de habilitación y confirmación de la tienda.'),
          ]),
          const Text(
              'Este borrador permanece solo mientras esta pantalla esté abierta. No se envió un pedido ni se realizó un cobro.'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: () => setState(() => _draft = null),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar datos')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver a mi lista')),
        ],
      );
}
