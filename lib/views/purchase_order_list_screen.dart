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

    String statusText;
    Color statusColor;
    if (docstatus == 0) {
      statusText = 'Borrador';
      statusColor = AppDesign.statusDraft;
    } else if (docstatus == 1) {
      statusText = 'Enviada';
      statusColor = AppDesign.statusSubmitted;
    } else {
      statusText = 'Cancelada';
      statusColor = AppDesign.statusCancelled;
    }

    return AppDesign.buildListCard(
      context: context,
      onTap: () async {
        context.read<PurchaseOrderProvider>().loadOrder(name);
        final result = await Navigator.pushNamed(context, '/po-detail');
        if (result == true && context.mounted) {
          context.read<PurchaseOrderProvider>().fetchOrders();
        }
      },
      child: Row(
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
                      ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(date) ?? DateTime.now())
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
    );
  }
}
