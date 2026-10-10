import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../data/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/pos_provider.dart';
import '../../services/api_service.dart';
import '../../services/print_service.dart';
import '../widgets/glass_card.dart';

class CheckoutModal extends StatefulWidget {
  const CheckoutModal({super.key});

  @override
  State<CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends State<CheckoutModal> {
  String _selectedMethod = 'EFECTIVO'; // EFECTIVO, QR, TARJETA, TRANSFERENCIA, MIXTO
  final _efectivoController = TextEditingController();
  final _qrController = TextEditingController();
  bool _isProcessing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final total = context.read<CartProvider>().totalAmount;
    _efectivoController.text = total.toStringAsFixed(2);
    _qrController.text = '0.00';
  }

  @override
  void dispose() {
    _efectivoController.dispose();
    _qrController.dispose();
    super.dispose();
  }

  double get _cambio {
    final total = context.read<CartProvider>().totalAmount;
    if (_selectedMethod == 'EFECTIVO') {
      final rec = double.tryParse(_efectivoController.text) ?? 0.0;
      return (rec - total) > 0 ? (rec - total) : 0.0;
    }
    return 0.0;
  }

  void _addEfectivo(double extra) {
    final total = context.read<CartProvider>().totalAmount;
    if (extra == 0) {
      _efectivoController.text = total.toStringAsFixed(2);
    } else {
      final actual = double.tryParse(_efectivoController.text) ?? total;
      _efectivoController.text = (actual + extra).toStringAsFixed(2);
    }
    setState(() {});
  }

  Future<void> _processCheckout() async {
    final cart = context.read<CartProvider>();
    final auth = context.read<AuthProvider>();
    final pos = context.read<PosProvider>();

    if (cart.items.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    final total = cart.totalAmount;
    final List<Map<String, dynamic>> pagos = [];
    final List<PaymentSplit> pagosSplit = [];

    if (_selectedMethod == 'MIXTO') {
      final mEf = double.tryParse(_efectivoController.text) ?? 0.0;
      final mQr = double.tryParse(_qrController.text) ?? 0.0;
      if ((mEf + mQr) < total) {
        setState(() {
          _isProcessing = false;
          _error = 'El total de los métodos combinados es menor a Bs. ${total.toStringAsFixed(2)}';
        });
        return;
      }
      pagos.add({'metodo': 'EFECTIVO', 'monto': mEf});
      pagos.add({'metodo': 'QR', 'monto': mQr});
      pagosSplit.add(PaymentSplit(metodo: 'EFECTIVO', monto: mEf));
      pagosSplit.add(PaymentSplit(metodo: 'QR', monto: mQr));
    } else {
      pagos.add({'metodo': _selectedMethod, 'monto': total});
      pagosSplit.add(PaymentSplit(metodo: _selectedMethod, monto: total));
    }

    // Preparar items
    final List<Map<String, dynamic>> itemsPayload = cart.items.map((it) {
      final map = <String, dynamic>{
        'id_producto': it.idProducto,
        'id_promocion': it.idPromocion,
        'cantidad': it.cantidad,
        'precio_unitario': it.unitPrice,
        'subtotal': it.subtotal,
      };
      if (it.acompanante != null) {
        map['acompanante'] = {
          'id_producto': it.acompanante!.idProducto,
          'nombre': it.acompanante!.nombre,
        };
      }
      return map;
    }).toList();

    try {
      final res = await ApiService.instance.crearComanda(
        idCajero: auth.currentUser?.id ?? 1,
        idMesero: auth.currentWaiter?.idMesero,
        items: itemsPayload,
        pagos: pagos,
        total: total,
        claveIdempotencia: cart.idempotencyKey,
      );

      if (res['success'] == true) {
        final idComanda = res['id_comanda'] as int;
        final fechaHora = res['fecha_hora']?.toString() ?? DateTime.now().toString();

        // Imprimir ticket nativo térmico
        final itemsCopia = List<CartItemModel>.from(cart.items);
        final config = pos.eventConfig ?? EventConfigModel(
          evento: 'MasterDrinks Evento',
          fecha: '',
          lugar: '',
          barra: 'Barra 1',
          responsable: '',
        );

        // Imprimir ticket
        if (mounted) {
          await PrintService.instance.imprimirTicket(
            context: context,
            idComanda: idComanda,
            config: config,
            cajeroNombre: auth.currentUser?.nombre ?? 'Cajero',
            meseroNombre: auth.currentWaiter?.nombre,
            items: itemsCopia,
            total: total,
            pagos: pagosSplit,
            fechaHora: fechaHora,
          );
        }

        // Vaciar carrito y actualizar stock
        cart.clearCart();
        await pos.refreshStock();

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _isProcessing = false;
          _error = res['message'] ?? 'Error al procesar comanda';
        });
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Error de conexión: $e';
      });
    }
  }

  Widget _buildMethodButton(String method, IconData icon) {
    final selected = _selectedMethod == method;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: () => setState(() => _selectedMethod = method),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? AppTheme.amberGold : AppTheme.surfaceGlass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppTheme.amberGold : AppTheme.borderGlass,
              ),
            ),
            child: Column(
              children: [
                Icon(icon, color: selected ? Colors.black : Colors.white70, size: 22),
                const SizedBox(height: 4),
                Text(
                  method,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.black : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final total = cart.totalAmount;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassCard(
          borderRadius: 24,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'COBRAR VENTA',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Total Destacado
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.amberGold.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL A PAGAR', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(
                      'Bs. ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.amberGold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Métodos de Pago
              Row(
                children: [
                  _buildMethodButton('EFECTIVO', Icons.payments_outlined),
                  _buildMethodButton('QR', Icons.qr_code),
                  _buildMethodButton('TARJETA', Icons.credit_card),
                  _buildMethodButton('TRANSFERENCIA', Icons.account_balance),
                ],
              ),
              const SizedBox(height: 16),

              // Sección según método
              if (_selectedMethod == 'EFECTIVO') ...[
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: TextField(
                        controller: _efectivoController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Efectivo Recibido (Bs.)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: AppTheme.surfaceGlass,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                        decoration: BoxDecoration(
                          color: _cambio > 0 ? Colors.green.withOpacity(0.15) : AppTheme.surfaceGlass,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _cambio > 0 ? Colors.greenAccent : AppTheme.borderGlass),
                        ),
                        child: Column(
                          children: [
                            const Text('CAMBIO', style: TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              'Bs. ${_cambio.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _cambio > 0 ? Colors.greenAccent : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Botones rápidos de billetes
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('Exacto'),
                      backgroundColor: AppTheme.surfaceGlass,
                      onPressed: () => _addEfectivo(0),
                    ),
                    ActionChip(
                      label: const Text('+20 Bs'),
                      backgroundColor: AppTheme.surfaceGlass,
                      onPressed: () => _addEfectivo(20),
                    ),
                    ActionChip(
                      label: const Text('+50 Bs'),
                      backgroundColor: AppTheme.surfaceGlass,
                      onPressed: () => _addEfectivo(50),
                    ),
                    ActionChip(
                      label: const Text('+100 Bs'),
                      backgroundColor: AppTheme.surfaceGlass,
                      onPressed: () => _addEfectivo(100),
                    ),
                    ActionChip(
                      label: const Text('+200 Bs'),
                      backgroundColor: AppTheme.surfaceGlass,
                      onPressed: () => _addEfectivo(200),
                    ),
                  ],
                ),
              ] else if (_selectedMethod == 'QR') ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGlass,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.borderGlass),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: AppTheme.amberGold, size: 36),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Muestra el QR en tu dispositivo al cliente y confirma una vez recibido el comprobante.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 24),

              // Botón Finalizar Cobro
              ElevatedButton(
                onPressed: _isProcessing ? null : _processCheckout,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: AppTheme.amberGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 10,
                  shadowColor: AppTheme.amberGold.withOpacity(0.5),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.print, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'CONFIRMAR E IMPRIMIR (Bs. ${total.toStringAsFixed(2)})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
