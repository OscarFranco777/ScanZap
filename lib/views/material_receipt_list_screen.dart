import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/material_receipt_provider.dart';
import '../services/erpnext_service.dart';
import '../theme/app_design.dart';

/// Pantalla de lista de Recepciones de Mercadería — diseño dashboard moderno.
class MaterialReceiptListScreen extends StatefulWidget {
  const MaterialReceiptListScreen({super.key});

  @override
  State<MaterialReceiptListScreen> createState() => _MaterialReceiptListScreenState();
}

class _MaterialReceiptListScreenState extends State<MaterialReceiptListScreen> {
  bool _statsExpanded = false;

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
                            'Resumen de Recepciones',
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
                                  icon: Icons.local_shipping_outlined,
                                  label: 'TOTAL RECEPCIONES',
                                  value: '${receipts.length}',
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
        onPressed: () => _showPOSelection(context),
        icon: Icons.add,
        label: 'Nueva Recepción',
        color: AppDesign.greenIcon,
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
                'Nueva Recepción de Mercadería',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // ─── Opción: Recepción Directa ───
                    AppDesign.buildListCard(
                      context: context,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/mr-create', arguments: {});
                      },
                      child: Row(
                        children: [
                          AppDesign.circleAvatar(
                            icon: Icons.add_circle_outline,
                            bgColor: AppDesign.tealLight,
                            iconColor: AppDesign.tealIcon,
                            size: 38,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Recepción Directa',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Crear recepción sin orden de compra',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ),

                    // ─── Separador ───
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey[300])),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Órdenes de Compra',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[400],
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey[300])),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ─── POs ───
                    if (provider.submittedPOs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: AppDesign.emptyState(
                          icon: Icons.shopping_cart_outlined,
                          title: 'No hay órdenes enviadas',
                        ),
                      )
                    else
                      for (final po in provider.submittedPOs)
                        _buildPOCard(context, provider, po, ctx),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPOCard(
    BuildContext context,
    MaterialReceiptProvider provider,
    Map<String, dynamic> po,
    BuildContext ctx,
  ) {
    final name = po['name'] ?? '';
    final supplier = po['supplier'] ?? '';
    final total = (po['grand_total'] ?? 0).toDouble();

    return AppDesign.buildListCard(
      context: context,
      onTap: () async {
        Navigator.pop(ctx);

        // Obtener datos de la PO para pre-llenar el modal
        try {
          final service = context.read<ErpNextService>();
          final poDetail = await service.getPODetailsForNewReceipt(name);
          if (!context.mounted) return;

          Navigator.pushNamed(context, '/mr-create', arguments: {
            'poName': name,
            'supplier': poDetail?['supplier'] ?? supplier,
            'supplierId': poDetail?['supplier'] ?? supplier,
            'warehouse': poDetail?['set_warehouse'] ?? '',
            'costCenter': poDetail?['cost_center'] ?? '',
          });
        } catch (e) {
          // Si falla, navegar sin datos pre-cargados
          if (context.mounted) {
            Navigator.pushNamed(context, '/mr-create', arguments: {
              'poName': name,
              'supplier': supplier,
              'supplierId': supplier,
            });
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
  }

  Widget _buildReceiptCard(BuildContext context, Map<String, dynamic> receipt) {
    final name = receipt['name'] ?? '';
    final supplier = receipt['supplier'] ?? '';
    final date = receipt['posting_date'] ?? '';
    final total = (receipt['grand_total'] ?? 0).toDouble();
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
                if (supplier.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    supplier,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
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
              if (total > 0) ...[
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
            ],
          ),
        ],
      ),
    );
  }
}
