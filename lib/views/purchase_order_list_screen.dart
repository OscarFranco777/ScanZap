import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';
import '../theme/app_design.dart';

/// Pantalla de lista de Órdenes de Compra — diseño dashboard moderno.
class PurchaseOrderListScreen extends StatefulWidget {
  const PurchaseOrderListScreen({super.key});

  @override
  State<PurchaseOrderListScreen> createState() => _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  bool _statsExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inventoryProvider = context.read<InventoryProvider>();
      final poProvider = context.read<PurchaseOrderProvider>();
      poProvider.loadItemsCache(inventoryProvider.itemsByCode);
      poProvider.fetchOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseOrderProvider>();
    final orders = provider.ordersList;

    // Contar por estado
    int drafts = 0, submitted = 0, cancelled = 0;
    for (final o in orders) {
      final ds = o['docstatus'] ?? 0;
      if (ds == 0) drafts++;
      if (ds == 1) submitted++;
      if (ds == 2) cancelled++;
    }

    return Scaffold(
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── Header ───
          AppDesign.buildHeader(
            title: 'Órdenes de Compra',
            subtitle: '${orders.length} órdenes registradas',
            icon: Icons.shopping_cart_outlined,
            onBack: () => Navigator.pop(context),
            actions: [
              GestureDetector(
                onTap: () => provider.fetchOrders(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.refresh, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),

          // ─── Stats (colapsable) ───
          GestureDetector(
            onTap: () => setState(() => _statsExpanded = !_statsExpanded),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppDesign.navy,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppDesign.navy.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 16,
                            color: AppDesign.accent,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Resumen de Órdenes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          AnimatedRotation(
                            turns: _statsExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Stats content (animated)
                    if (_statsExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          children: [
                            AppDesign.buildStatRow(
                              compact: true,
                              items: [
                                AppDesign.statBox(
                                  icon: Icons.shopping_cart_outlined,
                                  label: 'TOTAL ÓRDENES',
                                  value: '${orders.length}',
                                  compact: true,
                                ),
                                AppDesign.statBox(
                                  icon: Icons.edit_note,
                                  label: 'BORRADORES',
                                  value: '$drafts',
                                  valueColor: AppDesign.statusDraft,
                                  compact: true,
                                ),
                              ],
                            ),
                            AppDesign.buildStatRow(
                              compact: true,
                              items: [
                                AppDesign.statBox(
                                  icon: Icons.check_circle_outline,
                                  label: 'ENVIADAS',
                                  value: '$submitted',
                                  valueColor: AppDesign.statusSubmitted,
                                  compact: true,
                                ),
                                AppDesign.statBox(
                                  icon: Icons.cancel_outlined,
                                  label: 'CANCELADAS',
                                  value: '$cancelled',
                                  valueColor: AppDesign.statusCancelled,
                                  compact: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ─── Lista ───
          Expanded(
            child: provider.isLoading && orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? AppDesign.emptyState(
                        icon: Icons.shopping_cart_outlined,
                        title: 'No hay órdenes de compra',
                        subtitle: 'Presioná el botón + para crear una nueva',
                      )
                    : RefreshIndicator(
                        onRefresh: () => provider.fetchOrders(),
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 100),
                          children: [
                            AppDesign.sectionTitle('Lista de Órdenes'),
                            for (final order in orders)
                              _buildOrderCard(context, order),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: AppDesign.fab(
        onPressed: () async {
          context.read<PurchaseOrderProvider>().clearCurrentOrder();
          final result = await Navigator.pushNamed(context, '/po-create');
          if (result == true && context.mounted) {
            context.read<PurchaseOrderProvider>().fetchOrders();
          }
        },
        icon: Icons.add,
        label: 'Nueva Orden',
        color: AppDesign.orangeIcon,
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Map<String, dynamic> order) {
    final name = order['name'] ?? '';
    final supplier = order['supplier'] ?? '';
    final date = order['transaction_date'] ?? '';
    final total = (order['grand_total'] ?? 0).toDouble();
    final docstatus = order['docstatus'] ?? 0;

    // Estado REAL del ERP (el servidor es la única fuente de verdad)
    final erpStatus = (order['status'] ?? '').toString();
    final perBilled = (order['per_billed'] ?? 0 as num).toDouble();
    final perReceived = (order['per_received'] ?? 0 as num).toDouble();

    final statusText = _erpStatusLabel(docstatus, erpStatus);
    final statusColor = _erpStatusColor(docstatus, erpStatus);

    final canReceive =
        docstatus == 1 && perReceived < 100 && erpStatus != 'Closed';
    final canBill =
        docstatus == 1 && perBilled < 100 && erpStatus != 'Closed';

    return AppDesign.buildListCard(
      context: context,
      onTap: () async {
        context.read<PurchaseOrderProvider>().loadOrder(name);
        final result = await Navigator.pushNamed(context, '/po-detail');
        if (result == true && context.mounted) {
          context.read<PurchaseOrderProvider>().fetchOrders();
        }
      },
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              AppDesign.circleAvatar(
                icon: Icons.shopping_cart_outlined,
                bgColor: statusColor,
                iconColor: statusColor,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF1B2A4A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      supplier,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date.isNotEmpty
                          ? DateFormat('dd/MM/yyyy')
                              .format(DateTime.tryParse(date) ?? DateTime.now())
                          : '',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Status + Total
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppDesign.statusBadge(statusText, statusColor),
                  const SizedBox(height: 6),
                  Text(
                    'L ${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: Color(0xFF1B2A4A),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ─── Barras de progreso (órdenes enviadas) ───
          if (docstatus == 1) ...[
            const SizedBox(height: 10),
            _progressBar('Recibido', perReceived, AppDesign.tealIcon),
            const SizedBox(height: 5),
            _progressBar('Facturado', perBilled, AppDesign.blueIcon),
          ],

          // ─── Acciones rápidas (sin entrar al detalle) ───
          if (canReceive || canBill) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (canReceive)
                  Expanded(
                    child: _quickAction(
                      icon: Icons.local_shipping_outlined,
                      label: 'Recibir',
                      color: AppDesign.tealIcon,
                      onTap: () => _recibirFromCard(context, name),
                    ),
                  ),
                if (canReceive && canBill) const SizedBox(width: 8),
                if (canBill)
                  Expanded(
                    child: _quickAction(
                      icon: Icons.receipt_long_outlined,
                      label: 'Facturar',
                      color: AppDesign.blueIcon,
                      onTap: () => _facturarFromCard(context, name),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Barra de progreso compacta con etiqueta y %.
  Widget _progressBar(String label, double percent, Color color) {
    final pct = percent.clamp(0.0, 100.0);
    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 10),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 5,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '${pct.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  /// Botón de acción rápida compacto.
  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Etiqueta en español del estado real del ERP.
  String _erpStatusLabel(int docstatus, String erpStatus) {
    if (docstatus == 0) return 'Borrador';
    if (docstatus == 2 || erpStatus == 'Cancelled') return 'Cancelada';
    switch (erpStatus) {
      case 'To Receive and Bill':
        return 'Por recibir y facturar';
      case 'To Receive':
        return 'Por recibir';
      case 'To Bill':
        return 'Por facturar';
      case 'Completed':
        return 'Completada';
      case 'Closed':
        return 'Cerrada';
      case 'On Hold':
        return 'En espera';
      default:
        return erpStatus.isNotEmpty ? erpStatus : 'Enviada';
    }
  }

  /// Color según el estado real del ERP.
  Color _erpStatusColor(int docstatus, String erpStatus) {
    if (docstatus == 0) return AppDesign.statusDraft;
    if (docstatus == 2 || erpStatus == 'Cancelled') {
      return AppDesign.statusCancelled;
    }
    switch (erpStatus) {
      case 'Completed':
        return AppDesign.statusSubmitted;
      case 'To Receive':
      case 'To Bill':
        return AppDesign.blueIcon;
      case 'Closed':
        return AppDesign.statusCancelled;
      case 'On Hold':
        return AppDesign.orangeIcon;
      default: // To Receive and Bill, etc.
        return AppDesign.orangeIcon;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ACCIONES RÁPIDAS DESDE LA LISTA
  // ══════════════════════════════════════════════════════════════

  /// Recibir mercadería: carga la orden y abre el detalle con el
  /// formulario de recepción directo (argumento autoReceive).
  Future<void> _recibirFromCard(BuildContext context, String name) async {
    final provider = context.read<PurchaseOrderProvider>();
    await provider.loadOrder(name);
    if (!context.mounted) return;
    final result = await Navigator.pushNamed(context, '/po-detail',
        arguments: {'autoReceive': true});
    if (result == true && context.mounted) {
      context.read<PurchaseOrderProvider>().fetchOrders();
    }
  }

  /// Factura la orden completa desde la lista (sin abrir el detalle).
  Future<void> _facturarFromCard(BuildContext context, String name) async {
    final provider = context.read<PurchaseOrderProvider>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Facturar orden'),
        content: const Text(
          'Se creará y enviará una factura de proveedor por el pendiente de facturar.\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Facturar',
                style: TextStyle(color: AppDesign.statusSubmitted)),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    // Cargar la orden real del ERP y facturar el pendiente
    await provider.loadOrder(name);
    final order = provider.currentOrder;
    if (order == null || !provider.isSubmitted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${provider.error.isNotEmpty ? provider.error : "La orden debe estar enviada antes de facturar"}'),
            backgroundColor: AppDesign.statusCancelled,
          ),
        );
      }
      return;
    }

    final ok = await provider.createInvoiceForOrder();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '✅ Factura creada — orden al ${provider.currentOrder?.perBilled.toStringAsFixed(0) ?? 100}% facturado'
            : '❌ ${provider.error}'),
        backgroundColor:
            ok ? AppDesign.statusSubmitted : AppDesign.statusCancelled,
      ),
    );

    // Refrescar la lista para ver el nuevo estado
    await provider.fetchOrders();
  }
}
