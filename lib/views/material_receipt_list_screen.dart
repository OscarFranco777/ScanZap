import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/material_receipt_provider.dart';
import '../theme/app_design.dart';

/// Pantalla de lista de Recepciones de Mercadería — diseño dashboard moderno.
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
    final receipts = provider.receiptsList;

    int drafts = 0, submitted = 0, cancelled = 0;
    for (final r in receipts) {
      final ds = r['docstatus'] ?? 0;
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
            title: 'Recepción de Mercadería',
            subtitle: '${receipts.length} recepciones registradas',
            icon: Icons.local_shipping_outlined,
            onBack: () => Navigator.pop(context),
            actions: [
              GestureDetector(
                onTap: () => provider.fetchReceipts(),
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

          // ─── Stats ───
          AppDesign.buildStatsCard(
            children: [
              AppDesign.buildStatRow(
                items: [
                  AppDesign.statBox(
                    icon: Icons.local_shipping_outlined,
                    label: 'TOTAL RECEPCIONES',
                    value: '${receipts.length}',
                  ),
                  AppDesign.statBox(
                    icon: Icons.edit_note,
                    label: 'BORRADORES',
                    value: '$drafts',
                    valueColor: AppDesign.statusDraft,
                  ),
                ],
              ),
              AppDesign.buildStatRow(
                items: [
                  AppDesign.statBox(
                    icon: Icons.check_circle_outline,
                    label: 'ENVIADAS',
                    value: '$submitted',
                    valueColor: AppDesign.statusSubmitted,
                  ),
                  AppDesign.statBox(
                    icon: Icons.cancel_outlined,
                    label: 'CANCELADAS',
                    value: '$cancelled',
                    valueColor: AppDesign.statusCancelled,
                  ),
                ],
              ),
            ],
          ),

          // ─── Lista ───
          Expanded(
            child: provider.isLoading && receipts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : receipts.isEmpty
                    ? AppDesign.emptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No hay recepciones',
                        subtitle: 'Presioná el botón + para crear una nueva',
                      )
                    : RefreshIndicator(
                        onRefresh: () => provider.fetchReceipts(),
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 100),
                          children: [
                            AppDesign.sectionTitle('Lista de Recepciones'),
                            for (final receipt in receipts)
                              _buildReceiptCard(context, receipt),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: AppDesign.fab(
        onPressed: () => _showCreateOptions(context),
        icon: Icons.add,
        label: 'Nueva Recepción',
        color: AppDesign.greenIcon,
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Crear Recepción',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),

              // Opción: Desde PO
              _buildOptionTile(
                icon: Icons.shopping_cart_outlined,
                iconBg: AppDesign.blueLight,
                iconColor: AppDesign.blueIcon,
                title: 'Desde Orden de Compra',
                subtitle: 'Seleccionar PO enviada',
                onTap: () {
                  Navigator.pop(ctx);
                  _showPOSelection(context);
                },
              ),

              // Opción: Directa
              _buildOptionTile(
                icon: Icons.add_box_outlined,
                iconBg: AppDesign.greenLight,
                iconColor: AppDesign.greenIcon,
                title: 'Recepción Directa',
                subtitle: 'Crear desde cero',
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

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: AppDesign.circleAvatar(
        icon: icon,
        bgColor: iconBg,
        iconColor: iconColor,
        size: 44,
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[500], fontSize: 12),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  void _showPOSelection(BuildContext context) async {
    final provider = context.read<MaterialReceiptProvider>();
    await provider.fetchSubmittedPOs();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Seleccionar Orden de Compra',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: provider.submittedPOs.isEmpty
                    ? AppDesign.emptyState(
                        icon: Icons.shopping_cart_outlined,
                        title: 'No hay órdenes enviadas',
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: provider.submittedPOs.length,
                        itemBuilder: (context, index) {
                          final po = provider.submittedPOs[index];
                          final name = po['name'] ?? '';
                          final supplier = po['supplier'] ?? '';
                          final total = (po['grand_total'] ?? 0).toDouble();
                          return AppDesign.buildListCard(
                            context: context,
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
                            child: Row(
                              children: [
                                AppDesign.circleAvatar(
                                  icon: Icons.shopping_cart_outlined,
                                  bgColor: AppDesign.blueLight,
                                  iconColor: AppDesign.blueIcon,
                                  size: 38,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        supplier,
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'L ${total.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
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
        context.read<MaterialReceiptProvider>().loadReceipt(name);
        final result = await Navigator.pushNamed(context, '/mr-detail');
        if (result == true && context.mounted) {
          context.read<MaterialReceiptProvider>().fetchReceipts();
        }
      },
      child: Row(
        children: [
          AppDesign.circleAvatar(
            icon: Icons.local_shipping_outlined,
            bgColor: statusColor,
            iconColor: statusColor,
          ),
          const SizedBox(width: 12),
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
                  date.isNotEmpty
                      ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(date) ?? DateTime.now())
                      : '',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          AppDesign.statusBadge(statusText, statusColor),
        ],
      ),
    );
  }
}
