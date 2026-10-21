import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_invoice_provider.dart';
import '../theme/app_design.dart';

/// Pantalla de lista de Facturas de Compra — diseño dashboard moderno.
class PurchaseInvoiceListScreen extends StatefulWidget {
  const PurchaseInvoiceListScreen({super.key});

  @override
  State<PurchaseInvoiceListScreen> createState() =>
      _PurchaseInvoiceListScreenState();
}

class _PurchaseInvoiceListScreenState extends State<PurchaseInvoiceListScreen> {
  bool _statsExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inventoryProvider = context.read<InventoryProvider>();
      final piProvider = context.read<PurchaseInvoiceProvider>();
      piProvider.loadItemsCache(inventoryProvider.itemsByCode);
      piProvider.fetchInvoices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseInvoiceProvider>();
    final invoices = provider.invoicesList;

    int drafts = 0, submitted = 0, cancelled = 0;
    for (final i in invoices) {
      final ds = i['docstatus'] ?? 0;
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
            title: 'Facturas de Compra',
            subtitle: '${invoices.length} facturas registradas',
            icon: Icons.receipt_long_outlined,
            onBack: () => Navigator.pop(context),
            actions: [
              GestureDetector(
                onTap: () => provider.fetchInvoices(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 18,
                  ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 16,
                            color: AppDesign.accent,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Resumen de Facturas',
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
                                  icon: Icons.receipt_long_outlined,
                                  label: 'TOTAL FACTURAS',
                                  value: '${invoices.length}',
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
            child: provider.isLoading && invoices.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : invoices.isEmpty
                    ? AppDesign.emptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No hay facturas',
                        subtitle: 'Presioná el botón + para crear una nueva',
                      )
                    : RefreshIndicator(
                        onRefresh: () => provider.fetchInvoices(),
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 100),
                          children: [
                            AppDesign.sectionTitle('Lista de Facturas'),
                            for (final invoice in invoices)
                              _buildInvoiceCard(context, invoice),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: AppDesign.fab(
        onPressed: () {
          context.read<PurchaseInvoiceProvider>().clearCurrentInvoice();
          Navigator.pushNamed(context, '/pi-create');
        },
        icon: Icons.add,
        label: 'Nueva Factura',
        color: AppDesign.blueIcon,
      ),
    );
  }

  Widget _buildInvoiceCard(BuildContext context, Map<String, dynamic> invoice) {
    final name = invoice['name'] ?? '';
    final supplier = invoice['supplier'] ?? '';
    final billNo = (invoice['bill_no'] ?? '').toString();
    final date = invoice['posting_date'] ?? '';
    final total = (invoice['grand_total'] ?? 0).toDouble();
    final docstatus = invoice['docstatus'] ?? 0;

    // Estado REAL del ERP (el servidor es la única fuente de verdad)
    final erpStatus = (invoice['status'] ?? '').toString();

    final statusText = _erpStatusLabel(docstatus, erpStatus);
    final statusColor = _erpStatusColor(docstatus, erpStatus);

    return AppDesign.buildListCard(
      context: context,
      onTap: () async {
        context.read<PurchaseInvoiceProvider>().loadInvoice(name);
        final result = await Navigator.pushNamed(context, '/pi-detail');
        if (result == true && context.mounted) {
          context.read<PurchaseInvoiceProvider>().fetchInvoices();
        }
      },
      child: Column(
        children: [
          Row(
            children: [
              AppDesign.circleAvatar(
                icon: Icons.receipt_long_outlined,
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
                    if (billNo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Nº Prov: $billNo',
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
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
        ],
      ),
    );
  }

  /// Etiqueta en español del estado real del ERP del Purchase Invoice.
  String _erpStatusLabel(int docstatus, String erpStatus) {
    if (docstatus == 0) return 'Borrador';
    if (docstatus == 2 || erpStatus == 'Cancelled') return 'Cancelada';
    switch (erpStatus) {
      case 'Draft':
        return 'Borrador';
      case 'Return':
        return 'Devolución';
      case 'Return Issued':
        return 'Devolución emitida';
      case 'Paid':
        return 'Pagada';
      case 'Unpaid':
        return 'Sin pagar';
      case 'Overdue':
        return 'Vencida';
      case 'Partly Paid':
        return 'Pago parcial';
      case 'Internal Transfer':
        return 'Transferencia interna';
      default:
        return erpStatus.isNotEmpty ? erpStatus : 'Enviada';
    }
  }

  /// Color según el estado real del ERP del Purchase Invoice.
  Color _erpStatusColor(int docstatus, String erpStatus) {
    if (docstatus == 0) return AppDesign.statusDraft;
    if (docstatus == 2 || erpStatus == 'Cancelled') {
      return AppDesign.statusCancelled;
    }
    switch (erpStatus) {
      case 'Paid':
        return AppDesign.statusSubmitted;
      case 'Unpaid':
      case 'Partly Paid':
        return AppDesign.blueIcon;
      case 'Overdue':
        return AppDesign.statusCancelled;
      case 'Return':
      case 'Return Issued':
        return AppDesign.orangeIcon;
      default:
        return AppDesign.statusSubmitted;
    }
  }
}
