import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../data/models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/pos_provider.dart';
import '../../providers/server_provider.dart';
import '../widgets/companion_picker_dialog.dart';
import 'checkout_modal.dart';
import 'waiter_lock_screen.dart';
import 'server_screen.dart';
import 'login_screen.dart';
import 'admin/admin_main_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PosProvider>().loadCatalog();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onProductTap(ProductModel product) async {
    final cart = context.read<CartProvider>();
    final pos = context.read<PosProvider>();

    if (product.stockActual <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${product.nombre}" está agotado')),
      );
      return;
    }

    if (product.requiereAcompanante) {
      final acompanante = await showDialog<ProductModel>(
        context: context,
        builder: (_) => CompanionPickerDialog(
          product: product,
          companions: pos.companions,
        ),
      );

      if (acompanante != null) {
        cart.addProduct(product, acompanante: acompanante);
      }
    } else {
      cart.addProduct(product);
    }
  }

  void _onPromoTap(PromotionModel promo) {
    context.read<CartProvider>().addPromotion(promo);
  }

  void _openCheckout() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CheckoutModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final pos = context.watch<PosProvider>();
    final cart = context.watch<CartProvider>();
    final server = context.watch<ServerProvider>();

    return Stack(
      children: [
        Scaffold(
          body: Column(
            children: [
              // 1. Barra Superior del POS
              _buildTopBar(context, auth, pos, server),

              // 2. Contenido Principal: Catálogo a la izquierda + Carrito a la derecha
              Expanded(
                child: Row(
                  children: [
                    // Catálogo de Productos
                    Expanded(
                      flex: 7,
                      child: Column(
                        children: [
                          // Barra de Categorías y Búsqueda
                          _buildCategoryAndSearchBar(pos),

                          // Cuadrícula de Productos
                          Expanded(
                            child: pos.isLoading
                                ? const Center(child: CircularProgressIndicator(color: AppTheme.amberGold))
                                : _buildProductGrid(pos),
                          ),
                        ],
                      ),
                    ),

                    // Panel Lateral de Carrito
                    Container(
                      width: 380,
                      decoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: AppTheme.borderGlass, width: 1)),
                        color: Color(0xFF110E0B),
                      ),
                      child: _buildCartPanel(context, cart, auth),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 3. Pantalla de Bloqueo de Mesero si está activo el bloqueo
        if (auth.isWaiterLocked)
          Positioned.fill(
            child: WaiterLockScreen(
              onUnlocked: () {
                // Al desbloquear, se oculta el overlay y entra al POS
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, AuthProvider auth, PosProvider pos, ServerProvider server) {
    final config = pos.eventConfig;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF140F0B),
        border: Border(bottom: BorderSide(color: AppTheme.borderGlass)),
      ),
      child: Row(
        children: [
          // Logo & Datos del Evento
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [AppTheme.amberGold, AppTheme.orangeGlow]),
                ),
                child: const Icon(Icons.local_bar, color: Colors.black, size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config?.evento ?? 'Festival Sonidos de Verano 2026',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  Text(
                    config?.barra ?? 'Barra 1',
                    style: const TextStyle(fontSize: 12, color: AppTheme.amberGold, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),

          // Badge de Mesero
          InkWell(
            onTap: () => auth.lockWaiter(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.amberGold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.amberGold),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: AppTheme.amberGold, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    auth.currentWaiter != null
                        ? 'Mesero: ${auth.currentWaiter!.nombre}'
                        : 'Sin mesero (Toca para PIN)',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.amberGold),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.lock_outline, color: AppTheme.amberGold, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Badge de Cajero
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceGlass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.borderGlass),
            ),
            child: Row(
              children: [
                const Icon(Icons.point_of_sale, color: Colors.white70, size: 18),
                const SizedBox(width: 6),
                Text(
                  auth.currentUser?.nombre ?? 'Cajero',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Indicador Servidor
          InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServerScreen())),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: server.isServerRunning ? Colors.green.withOpacity(0.15) : AppTheme.surfaceGlass,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: server.isServerRunning ? Colors.greenAccent : AppTheme.borderGlass),
              ),
              child: Row(
                children: [
                  Icon(Icons.dns, size: 16, color: server.isServerRunning ? Colors.greenAccent : Colors.white60),
                  const SizedBox(width: 6),
                  Text(
                    server.isServerRunning ? '${server.serverIp}:${server.serverPort}' : 'Servidor',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: server.isServerRunning ? Colors.greenAccent : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Acceso Admin (si tiene rol)
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: AppTheme.amberGold),
              tooltip: 'Panel de Administración',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AdminMainScreen()),
                );
              },
            ),

          // Cerrar Sesión
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white60),
            tooltip: 'Cerrar Sesión',
            onPressed: () {
              auth.logout();
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryAndSearchBar(PosProvider pos) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF16120E),
        border: Border(bottom: BorderSide(color: AppTheme.borderGlass)),
      ),
      child: Row(
        children: [
          // Selector de Categorías (Pills)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCategoryPill('Todas', null, pos),
                  _buildCategoryPill('⭐ Promociones', -99, pos),
                  ...pos.categories.map((cat) {
                    return _buildCategoryPill(cat.nombre, cat.idCategoria, pos);
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Buscador rápido
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white54),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          pos.setSearchQuery('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surfaceGlass,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              ),
              onChanged: (val) => pos.setSearchQuery(val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPill(String title, int? id, PosProvider pos) {
    final selected = pos.selectedCategoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(title),
        labelStyle: TextStyle(
          color: selected ? Colors.black : Colors.white70,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        backgroundColor: AppTheme.surfaceGlass,
        selectedColor: AppTheme.amberGold,
        checkmarkColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: selected ? AppTheme.amberGold : AppTheme.borderGlass),
        onSelected: (_) => pos.setSelectedCategory(id),
      ),
    );
  }

  Widget _buildProductGrid(PosProvider pos) {
    final items = pos.filteredItems;

    if (items.isEmpty) {
      return const Center(
        child: Text('No hay productos que coincidan', style: TextStyle(color: Colors.white54)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.88,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        if (item is PromotionModel) {
          return _buildPromoCard(item);
        } else if (item is ProductModel) {
          return _buildProductCard(item);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildProductCard(ProductModel p) {
    final sinStock = p.stockActual <= 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: sinStock ? null : () => _onProductTap(p),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: sinStock ? Colors.white.withOpacity(0.02) : AppTheme.surfaceGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: sinStock ? Colors.white12 : AppTheme.borderGlass,
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stock Badge superior
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: sinStock
                          ? Colors.red.withOpacity(0.2)
                          : (p.stockActual < 15 ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      sinStock ? 'AGOTADO' : 'Stock: ${p.stockActual}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: sinStock
                            ? Colors.redAccent
                            : (p.stockActual < 15 ? Colors.orangeAccent : Colors.greenAccent),
                      ),
                    ),
                  ),
                  if (p.requiereAcompanante)
                    const Tooltip(
                      message: 'Incluye mezclador',
                      child: Icon(Icons.add_circle_outline, color: AppTheme.amberGold, size: 16),
                    ),
                ],
              ),
              const Spacer(),

              // Nombre del producto
              Text(
                p.nombre,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: sinStock ? Colors.white38 : Colors.white,
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // Precio
              Text(
                'Bs. ${p.precioVenta.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: sinStock ? Colors.white38 : AppTheme.amberGold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromoCard(PromotionModel promo) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onPromoTap(promo),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2E1C0A),
                AppTheme.surfaceGlass,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.amberGold.withOpacity(0.6), width: 1.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.amberGold,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'COMBO PROMO',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              const Spacer(),
              Text(
                promo.nombre,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                promo.descripcion ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                'Bs. ${promo.precio.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.amberGold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartPanel(BuildContext context, CartProvider cart, AuthProvider auth) {
    return Column(
      children: [
        // Cabecera del Carrito
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.borderGlass)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, color: AppTheme.amberGold, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'ORDEN ACTUAL (${cart.totalItemsCount})',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white),
                  ),
                ],
              ),
              if (cart.items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
                  tooltip: 'Vaciar orden',
                  onPressed: () => cart.clearCart(),
                ),
            ],
          ),
        ),

        // Lista de items del carrito
        Expanded(
          child: cart.items.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long, size: 48, color: Colors.white24),
                      SizedBox(height: 12),
                      Text('No hay bebidas en la comanda', style: TextStyle(color: Colors.white38, fontSize: 13)),
                      SizedBox(height: 4),
                      Text('Toca productos a la izquierda para añadir', style: TextStyle(color: Colors.white24, fontSize: 11)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = cart.items[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGlass,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderGlass),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                ),
                              ),
                              Text(
                                'Bs. ${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppTheme.amberGold),
                              ),
                            ],
                          ),
                          if (item.acompanante != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '+ Mezclador: ${item.acompanante!.nombre} (Gratis)',
                              style: const TextStyle(fontSize: 11, color: Colors.white60),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Bs. ${item.unitPrice.toStringAsFixed(2)} c/u',
                                style: const TextStyle(fontSize: 11, color: Colors.white38),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.white70),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => cart.decrementQuantity(index),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Text(
                                      '${item.cantidad}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 20, color: AppTheme.amberGold),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => cart.incrementQuantity(index),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => cart.removeItem(index),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Pie del Carrito: Totales y Botón Cobrar
        Container(
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: Color(0xFF16120E),
            border: Border(top: BorderSide(color: AppTheme.borderGlass)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL COMANDA', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(
                    'Bs. ${cart.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.amberGold),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: cart.items.isEmpty ? null : _openCheckout,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: AppTheme.amberGold,
                  foregroundColor: Colors.black,
                  elevation: 8,
                  shadowColor: AppTheme.amberGold.withOpacity(0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.payment, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'COBRAR · Bs. ${cart.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
