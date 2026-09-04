import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';

/// Pantalla de lista de Órdenes de Compra.
class PurchaseOrderListScreen extends StatefulWidget {
  const PurchaseOrderListScreen({super.key});

  @override
  State<PurchaseOrderListScreen> createState() => _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Sincronizar caché de items del inventario
      final inventoryProvider = context.read<InventoryProvider>();
      final poProvider = context.read<PurchaseOrderProvider>();
      poProvider.loadItemsCache(inventoryProvider.itemsByCode);
      poProvider.fetchOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseOrderProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('🛒 Órdenes de Compra'),
        actions: [
          IconButton(
            onPressed: () => provider.fetchOrders(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: provider.isLoading && provider.ordersList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.ordersList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'No hay órdenes de compra',
                        style: TextStyle(color: Colors.grey[500], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Presioná + para crear una nueva',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => provider.fetchOrders(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: provider.ordersList.length,
                    itemBuilder: (context, index) {
                      final order = provider.ordersList[index];
                      return _buildOrderCard(context, order);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/po-create'),
        icon: const Icon(Icons.add),
        label: const Text('Nueva Orden'),
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
      statusColor = Colors.orange;
    } else if (docstatus == 1) {
      statusText = 'Enviada';
      statusColor = Colors.green;
    } else {
      statusText = 'Cancelada';
      statusColor = Colors.red;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(Icons.shopping_cart, color: statusColor, size: 20),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              supplier,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            Text(
              date.isNotEmpty ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(date) ?? DateTime.now()) : '',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'L ${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
        onTap: () {
          // Cargar orden y navegar a detalle
          context.read<PurchaseOrderProvider>().loadOrder(name);
          Navigator.pushNamed(context, '/po-detail');
        },
      ),
    );
  }
}
