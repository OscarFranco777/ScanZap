import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/material_receipt_provider.dart';

/// Pantalla de lista de Recepciones de Mercadería.
class MaterialReceiptListScreen extends StatefulWidget {
  const MaterialReceiptListScreen({super.key});

  @override
  State<MaterialReceiptListScreen> createState() => _MaterialReceiptListScreenState();
}

class _MaterialReceiptListScreenState extends State<MaterialReceiptListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inventoryProvider = context.read<InventoryProvider>();
      final mrProvider = context.read<MaterialReceiptProvider>();
      mrProvider.loadItemsCache(inventoryProvider.itemsByCode);
      mrProvider.fetchReceipts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialReceiptProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📦 Recepción de Mercadería'),
        actions: [
          IconButton(
            onPressed: () => provider.fetchReceipts(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: provider.isLoading && provider.receiptsList.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.receiptsList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      Text(
                        'No hay recepciones',
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
                  onRefresh: () => provider.fetchReceipts(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: provider.receiptsList.length,
                    itemBuilder: (context, index) {
                      final receipt = provider.receiptsList[index];
                      return _buildReceiptCard(context, receipt);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateOptions(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva Recepción'),
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Crear Recepción',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: Icon(Icons.shopping_cart_outlined, color: Colors.blue),
              title: Text('Desde Orden de Compra'),
              subtitle: Text('Seleccionar PO enviada'),
              onTap: () {
                Navigator.pop(ctx);
                _showPOSelection(context);
              },
            ),
            Divider(height: 1),
            ListTile(
              leading: Icon(Icons.add_box_outlined, color: Colors.green),
              title: Text('Recepción Directa'),
              subtitle: Text('Crear desde cero'),
              onTap: () async {
                Navigator.pop(ctx);
                context.read<MaterialReceiptProvider>().clearCurrentReceipt();
                context.read<MaterialReceiptProvider>().createNewReceipt();
                final result = await Navigator.pushNamed(context, '/mr-create');
                if (result == true && context.mounted) {
                  context.read<MaterialReceiptProvider>().fetchReceipts();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPOSelection(BuildContext context) async {
    final provider = context.read<MaterialReceiptProvider>();
    await provider.fetchSubmittedPOs();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Seleccionar Orden de Compra',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: provider.submittedPOs.isEmpty
                  ? Center(child: Text('No hay órdenes enviadas'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: provider.submittedPOs.length,
                      itemBuilder: (context, index) {
                        final po = provider.submittedPOs[index];
                        final name = po['name'] ?? '';
                        final supplier = po['supplier'] ?? '';
                        final total = (po['grand_total'] ?? 0).toDouble();
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue[100],
                            child: Icon(Icons.shopping_cart, size: 18, color: Colors.blue),
                          ),
                          title: Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(supplier, style: TextStyle(fontSize: 12)),
                          trailing: Text(
                            'L ${total.toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await provider.createFromPO(name);
                            if (context.mounted) {
                              final result = await Navigator.pushNamed(context, '/mr-create');
                              if (result == true && context.mounted) {
                                provider.fetchReceipts();
                              }
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, Map<String, dynamic> receipt) {
    final name = receipt['name'] ?? '';
    final date = receipt['posting_date'] ?? '';
    final docstatus = receipt['docstatus'] ?? 0;

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
          child: Icon(Icons.inventory_2, color: statusColor, size: 20),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          date.isNotEmpty ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(date) ?? DateTime.now()) : '',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        trailing: Container(
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
        onTap: () async {
          context.read<MaterialReceiptProvider>().loadReceipt(name);
          final result = await Navigator.pushNamed(context, '/mr-detail');
          if (result == true && context.mounted) {
            context.read<MaterialReceiptProvider>().fetchReceipts();
          }
        },
      ),
    );
  }
}
