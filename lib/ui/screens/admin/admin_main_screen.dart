import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../data/models/models.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/pos_provider.dart';
import '../../widgets/glass_card.dart';
import '../pos_screen.dart';
import '../server_screen.dart';

class AdminMainScreen extends StatefulWidget {
  const AdminMainScreen({super.key});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final admin = context.read<AdminProvider>();
      admin.loadConfig();
      admin.loadReporte();
      admin.loadPersonal();
      admin.loadComandas();
      admin.loadAuditoria();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings, color: AppTheme.amberGold),
            const SizedBox(width: 10),
            const Text('Panel de Administración'),
            const SizedBox(width: 14),
            Text(
              '· ${admin.config?.barra ?? "Barra 1"}',
              style: const TextStyle(fontSize: 14, color: AppTheme.amberGold, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF140F0B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.point_of_sale, color: AppTheme.amberGold),
            tooltip: 'Ir a Punto de Venta (POS)',
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const PosScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.dns, color: Colors.greenAccent),
            tooltip: 'Servidor y Red',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: AppTheme.amberGold,
          labelColor: AppTheme.amberGold,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Resumen'),
            Tab(icon: Icon(Icons.event_note), text: 'Datos Evento'),
            Tab(icon: Icon(Icons.people_outline), text: 'Personal'),
            Tab(icon: Icon(Icons.local_bar_outlined), text: 'Catálogo'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Stock'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Comandas'),
            Tab(icon: Icon(Icons.history_edu), text: 'Auditoría'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(admin),
          _buildEventConfigTab(admin),
          _buildPersonnelTab(admin),
          _buildCatalogTab(admin),
          _buildStockTab(admin),
          _buildOrdersTab(admin),
          _buildAuditTab(admin),
        ],
      ),
    );
  }

  // 1. PESTAÑA: RESUMEN / DASHBOARD
  Widget _buildDashboardTab(AdminProvider admin) {
    final rep = admin.reporte;
    final tot = (rep['totales'] as Map<String, dynamic>?) ?? {};
    final metodos = (rep['metodos_pago'] as List?) ?? [];
    final productos = (rep['productos'] as List?) ?? [];
    final meseros = (rep['meseros'] as List?) ?? [];

    final totalVentas = (tot['total_ventas'] is num) ? (tot['total_ventas'] as num).toDouble() : 0.0;
    final totalComandas = tot['total_comandas'] ?? 0;
    final ticketPromedio = totalComandas > 0 ? (totalVentas / totalComandas) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tarjetas de Métricas Rápidas
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'VENTAS TOTALES',
                  'Bs. ${totalVentas.toStringAsFixed(2)}',
                  Icons.monetization_on,
                  AppTheme.amberGold,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  'TOTAL COMANDAS',
                  '$totalComandas',
                  Icons.receipt,
                  Colors.cyanAccent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildMetricCard(
                  'TICKET PROMEDIO',
                  'Bs. ${ticketPromedio.toStringAsFixed(2)}',
                  Icons.analytics_outlined,
                  Colors.greenAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Botón destacado: Generar Cierre de Caja en PDF
          ElevatedButton.icon(
            onPressed: () => admin.exportarPdfCierre(),
            icon: const Icon(Icons.picture_as_pdf, size: 24),
            label: const Text(
              'DESCARGAR / IMPRIMIR REPORTE DE CIERRE OFICIAL (PDF)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amberGold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 24),

          // Sección de Métodos de Pago y Top Productos
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Desglose Métodos de Pago
              Expanded(
                flex: 4,
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POR MÉTODO DE PAGO',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                      const SizedBox(height: 14),
                      if (metodos.isEmpty)
                        const Text('Sin ventas registradas', style: TextStyle(color: Colors.white54))
                      else
                        ...metodos.map((m) {
                          final monto = (m['monto'] is num) ? (m['monto'] as num).toDouble() : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(m['metodo'] ?? '', style: const TextStyle(color: Colors.white70)),
                                Text('Bs. ${monto.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Top Productos
              Expanded(
                flex: 6,
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PRODUCTOS MÁS VENDIDOS',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                      const SizedBox(height: 14),
                      if (productos.isEmpty)
                        const Text('Sin productos vendidos', style: TextStyle(color: Colors.white54))
                      else
                        ...productos.take(6).map((p) {
                          final cant = p['total_unidades'] ?? 0;
                          final rec = (p['total_recaudado'] is num) ? (p['total_recaudado'] as num).toDouble() : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(child: Text(p['nombre'] ?? '', style: const TextStyle(color: Colors.white70))),
                                Text('$cant un.  ·  ', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                Text('Bs. ${rec.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.amberGold)),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Rendimiento de Meseros
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VENTAS POR MESERO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 14),
                if (meseros.isEmpty)
                  const Text('No hay ventas registradas por meseros', style: TextStyle(color: Colors.white54))
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: meseros.map((m) {
                      final tot = (m['total'] is num) ? (m['total'] as num).toDouble() : 0.0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGlass,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderGlass),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person, size: 16, color: AppTheme.amberGold),
                            const SizedBox(width: 8),
                            Text(m['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(width: 8),
                            Text('Bs. ${tot.toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.amberGold)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54)),
                const SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2. PESTAÑA: DATOS DEL EVENTO (CONFIGURACIÓN)
  Widget _buildEventConfigTab(AdminProvider admin) {
    final cfg = admin.config;
    final eventoController = TextEditingController(text: cfg?.evento ?? '');
    final fechaController = TextEditingController(text: cfg?.fecha ?? '');
    final lugarController = TextEditingController(text: cfg?.lugar ?? '');
    final barraController = TextEditingController(text: cfg?.barra ?? '');
    final respController = TextEditingController(text: cfg?.responsable ?? '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: GlassCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Configuración del Evento', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 6),
                const Text('Estos datos se reflejan en la cabecera del POS, tickets y reportes.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 24),

                TextField(
                  controller: eventoController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Nombre del Evento', filled: true, fillColor: AppTheme.surfaceGlass),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: fechaController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Fecha del Evento (YYYY-MM-DD)', filled: true, fillColor: AppTheme.surfaceGlass),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: lugarController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Lugar / Estadio', filled: true, fillColor: AppTheme.surfaceGlass),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: barraController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Nombre de esta Barra (Ej: Barra 1 / Barra VIP)', filled: true, fillColor: AppTheme.surfaceGlass),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: respController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Responsable / Administrador', filled: true, fillColor: AppTheme.surfaceGlass),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () async {
                    final ok = await admin.updateConfig(
                      EventConfigModel(
                        evento: eventoController.text.trim(),
                        fecha: fechaController.text.trim(),
                        lugar: lugarController.text.trim(),
                        barra: barraController.text.trim(),
                        responsable: respController.text.trim(),
                      ),
                    );
                    if (ok && mounted) {
                      context.read<PosProvider>().loadCatalog();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Configuración del evento guardada exitosamente')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amberGold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('GUARDAR CAMBIOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 3. PESTAÑA: PERSONAL (CAJEROS Y MESEROS)
  Widget _buildPersonnelTab(AdminProvider admin) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cajeros
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cajeros Registrados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ElevatedButton.icon(
                onPressed: () => _dialogCrearCajero(context, admin),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo Cajero'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: admin.cajeros.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final c = admin.cajeros[index];
              return ListTile(
                tileColor: AppTheme.surfaceGlass,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.borderGlass)),
                leading: const Icon(Icons.person, color: AppTheme.amberGold),
                title: Text(c['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('Usuario: ${c['usuario']}', style: const TextStyle(color: Colors.white60)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => admin.eliminarCajero(c['id_cajero'] as int),
                ),
              );
            },
          ),
          const SizedBox(height: 28),

          // Meseros
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Meseros (${admin.meseros.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ElevatedButton.icon(
                onPressed: () => _dialogCrearMesero(context, admin),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo Mesero'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: admin.meseros.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final m = admin.meseros[index];
              return ListTile(
                tileColor: AppTheme.surfaceGlass,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.borderGlass)),
                leading: const Icon(Icons.badge, color: AppTheme.amberGold),
                title: Text(m['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('PIN: ${m['password']} · Usuario: ${m['usuario']}', style: const TextStyle(color: Colors.white60)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => admin.eliminarMesero(m['id_mesero'] as int),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _dialogCrearCajero(BuildContext context, AdminProvider admin) {
    final nom = TextEditingController();
    final usu = TextEditingController();
    final pass = TextEditingController(text: 'demo123');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B140F),
        title: const Text('Nuevo Cajero', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nombre Completo')),
            const SizedBox(height: 10),
            TextField(controller: usu, decoration: const InputDecoration(labelText: 'Usuario')),
            const SizedBox(height: 10),
            TextField(controller: pass, decoration: const InputDecoration(labelText: 'Contraseña')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nom.text.isNotEmpty && usu.text.isNotEmpty) {
                await admin.crearCajero(nom.text, usu.text, pass.text);
                if (context.mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _dialogCrearMesero(BuildContext context, AdminProvider admin) {
    final nom = TextEditingController();
    final usu = TextEditingController();
    final pin = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B140F),
        title: const Text('Nuevo Mesero', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nombre Completo')),
            const SizedBox(height: 10),
            TextField(controller: usu, decoration: const InputDecoration(labelText: 'Usuario')),
            const SizedBox(height: 10),
            TextField(controller: pin, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN de 4 dígitos')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (nom.text.isNotEmpty && pin.text.isNotEmpty) {
                await admin.crearMesero(nom.text, usu.text, pin.text, 1);
                if (context.mounted) Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  // 4. PESTAÑA: CATÁLOGO DE PRODUCTOS
  Widget _buildCatalogTab(AdminProvider admin) {
    final pos = context.watch<PosProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Catálogo de Productos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ElevatedButton.icon(
                onPressed: () => _dialogCrearProducto(context, admin, pos),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo Producto'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pos.products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = pos.products[index];
              return ListTile(
                tileColor: AppTheme.surfaceGlass,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.borderGlass)),
                leading: const Icon(Icons.liquor, color: AppTheme.amberGold),
                title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('Bs. ${p.precioVenta.toStringAsFixed(2)} · Stock: ${p.stockActual}', style: const TextStyle(color: Colors.white60)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await admin.eliminarProducto(p.idProducto);
                    pos.loadCatalog();
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _dialogCrearProducto(BuildContext context, AdminProvider admin, PosProvider pos) {
    final nom = TextEditingController();
    final precio = TextEditingController();
    final stock = TextEditingController(text: '50');
    int idCat = pos.categories.isNotEmpty ? pos.categories.first.idCategoria : 1;
    bool reqAcomp = false;
    bool esAcomp = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B140F),
          title: const Text('Nuevo Producto', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nom, decoration: const InputDecoration(labelText: 'Nombre del Producto')),
                const SizedBox(height: 10),
                TextField(controller: precio, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio de Venta (Bs.)')),
                const SizedBox(height: 10),
                TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock Inicial')),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: idCat,
                  items: pos.categories.map((c) => DropdownMenuItem(value: c.idCategoria, child: Text(c.nombre))).toList(),
                  onChanged: (v) => setDialogState(() => idCat = v ?? 1),
                  decoration: const InputDecoration(labelText: 'Categoría'),
                ),
                CheckboxListTile(
                  title: const Text('Requiere acompañante (Botella)', style: TextStyle(fontSize: 13, color: Colors.white)),
                  value: reqAcomp,
                  onChanged: (v) => setDialogState(() => reqAcomp = v ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Es acompañante / mezclador', style: TextStyle(fontSize: 13, color: Colors.white)),
                  value: esAcomp,
                  onChanged: (v) => setDialogState(() => esAcomp = v ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                if (nom.text.isNotEmpty && precio.text.isNotEmpty) {
                  await admin.crearProducto({
                    'nombre': nom.text,
                    'precio_venta': double.tryParse(precio.text) ?? 0.0,
                    'stock_actual': int.tryParse(stock.text) ?? 0,
                    'id_categoria': idCat,
                    'requiere_acompanante': reqAcomp ? 1 : 0,
                    'es_acompanante': esAcomp ? 1 : 0,
                  });
                  pos.loadCatalog();
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  // 5. PESTAÑA: STOCK E INVENTARIO
  Widget _buildStockTab(AdminProvider admin) {
    final pos = context.watch<PosProvider>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Inventario y Ajustes de Stock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ElevatedButton.icon(
                onPressed: () => _dialogAjusteStock(context, admin, pos),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Ajuste Rápido'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pos.products.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final p = pos.products[index];
              return ListTile(
                tileColor: AppTheme.surfaceGlass,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.borderGlass)),
                title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('Precio: Bs. ${p.precioVenta.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white60)),
                trailing: Text(
                  '${p.stockActual} unidades',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: p.stockActual > 15 ? Colors.greenAccent : (p.stockActual > 0 ? Colors.orangeAccent : Colors.redAccent),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _dialogAjusteStock(BuildContext context, AdminProvider admin, PosProvider pos) {
    int idProd = pos.products.isNotEmpty ? pos.products.first.idProducto : 1;
    String tipo = 'ENTRADA'; // ENTRADA, SALIDA, AJUSTE
    final cant = TextEditingController(text: '10');
    final motivo = TextEditingController(text: 'Ingreso de mercancía');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1B140F),
          title: const Text('Ajustar Stock', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: idProd,
                items: pos.products.map((p) => DropdownMenuItem(value: p.idProducto, child: Text(p.nombre))).toList(),
                onChanged: (v) => setDialogState(() => idProd = v ?? 1),
                decoration: const InputDecoration(labelText: 'Producto'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: tipo,
                items: const [
                  DropdownMenuItem(value: 'ENTRADA', child: Text('ENTRADA (Añadir unidades)')),
                  DropdownMenuItem(value: 'SALIDA', child: Text('SALIDA (Retirar unidades)')),
                  DropdownMenuItem(value: 'AJUSTE', child: Text('AJUSTE (Fijar número exacto)')),
                ],
                onChanged: (v) => setDialogState(() => tipo = v ?? 'ENTRADA'),
                decoration: const InputDecoration(labelText: 'Tipo de Movimiento'),
              ),
              const SizedBox(height: 10),
              TextField(controller: cant, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
              const SizedBox(height: 10),
              TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo / Justificación')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                final c = int.tryParse(cant.text) ?? 0;
                if (c > 0) {
                  await admin.registrarAjusteStock(idProd, tipo, c, motivo.text, 1);
                  pos.refreshStock();
                  if (ctx.mounted) Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amberGold, foregroundColor: Colors.black),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  // 6. PESTAÑA: HISTORIAL DE COMANDAS & ANULACIÓN
  Widget _buildOrdersTab(AdminProvider admin) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Historial de Comandas (${admin.comandas.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              IconButton(
                icon: const Icon(Icons.refresh, color: AppTheme.amberGold),
                onPressed: () => admin.loadComandas(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (admin.comandas.isEmpty)
            const Center(child: Text('No hay comandas registradas aún', style: TextStyle(color: Colors.white54)))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: admin.comandas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final c = admin.comandas[index];
                final anulada = c['estatus'] == 'ANULADA';
                final total = (c['total'] is num) ? (c['total'] as num).toDouble() : 0.0;

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: anulada ? Colors.red.withOpacity(0.08) : AppTheme.surfaceGlass,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: anulada ? Colors.redAccent.withOpacity(0.4) : AppTheme.borderGlass),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('COMANDA #${c["id_comanda"]}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: anulada ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              c['estatus'] ?? 'COMPLETADA',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: anulada ? Colors.redAccent : Colors.greenAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Fecha: ${c["fecha_hora"]} · Cajero: ${c["cajero_nombre"] ?? "N/A"} · Mesero: ${c["mesero_nombre"] ?? "N/A"}',
                        style: const TextStyle(fontSize: 12, color: Colors.white60),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total: Bs. ${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: AppTheme.amberGold),
                          ),
                          if (!anulada)
                            TextButton.icon(
                              onPressed: () => _dialogAnularComanda(context, admin, c['id_comanda'] as int),
                              icon: const Icon(Icons.cancel_outlined, color: Colors.redAccent, size: 16),
                              label: const Text('Anular Comanda', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _dialogAnularComanda(BuildContext context, AdminProvider admin, int idComanda) {
    final motivo = TextEditingController(text: 'Error de cobro / cliente canceló');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B140F),
        title: Text('Anular Comanda #$idComanda', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Al anular la comanda, el stock de las bebidas vendidas se restituirá automáticamente al inventario y se registrará en la auditoría.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo de anulación')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              await admin.anularComanda(idComanda, 1, motivo.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Anular y Devolver Stock'),
          ),
        ],
      ),
    );
  }

  // 7. PESTAÑA: AUDITORÍA
  Widget _buildAuditTab(AdminProvider admin) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Bitácora de Auditoría del Administrador', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: admin.auditoria.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final a = admin.auditoria[index];
              return ListTile(
                tileColor: AppTheme.surfaceGlass,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.borderGlass)),
                leading: const Icon(Icons.shield_outlined, color: AppTheme.amberGold),
                title: Text('${a["accion"]} · ${a["entidad"]}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                subtitle: Text('${a["detalle"]}\n${a["fecha_hora"]}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
              );
            },
          ),
        ],
      ),
    );
  }
}
