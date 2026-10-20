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
  State<MaterialReceiptListScreen> createState() =>
      _MaterialReceiptListScreenState();
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
        onPressed: () {
          context.read<MaterialReceiptProvider>().clearCurrentReceipt();
          Navigator.pushNamed(context, '/mr-create');
        },
        icon: Icons.add,
        label: 'Nueva Recepción',
        color: AppDesign.greenIcon,
      ),
    );
  }

  Widget _buildReceiptCard(BuildContext context, Map<String, dynamic> receipt) {
    final name = receipt['name'] ?? '';
    final supplier = receipt['supplier'] ?? '';
    final date = receipt['posting_date'] ?? '';
    final total = (receipt['grand_total'] ?? 0).toDouble();
    final docstatus = receipt['docstatus'] ?? 0;

    // Estado REAL del ERP (el servidor es la única fuente de verdad)
    final erpStatus = (receipt['status'] ?? '').toString();
    final perBilled = (receipt['per_billed'] is num)
        ? (receipt['per_billed'] as num).toDouble()
        : 0.0;

    final statusText = _erpStatusLabel(docstatus, erpStatus);
    final statusColor = _erpStatusColor(docstatus, erpStatus);

    final canBill =
        docstatus == 1 &&
        perBilled < 100 &&
        erpStatus != 'Closed' &&
        erpStatus != 'Cancelled' &&
        erpStatus != 'Return' &&
        erpStatus != 'Return Issued';

    return AppDesign.buildListCard(
      context: context,
      onTap: () async {
        context.read<MaterialReceiptProvider>().loadReceipt(name);
        final result = await Navigator.pushNamed(context, '/mr-detail');
        if (result == true && context.mounted) {
          context.read<MaterialReceiptProvider>().fetchReceipts();
        }
      },
      child: Column(
        children: [
          Row(
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
                          ? DateFormat(
                              'dd/MM/yyyy',
                            ).format(DateTime.tryParse(date) ?? DateTime.now())
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

          // ─── Barra de progreso (recepciones enviadas) ───
          if (docstatus == 1) ...[
            const SizedBox(height: 10),
            _progressBar('Facturado', perBilled, AppDesign.blueIcon),
          ],

          // ─── Acción rápida (sin entrar al detalle) ───
          if (canBill) ...[
            const SizedBox(height: 10),
            _quickAction(
              icon: Icons.receipt_long_outlined,
              label: 'Facturar',
              color: AppDesign.blueIcon,
              onTap: () => _facturarFromCard(context, name),
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

  /// Etiqueta en español del estado real del ERP del Purchase Receipt.
  String _erpStatusLabel(int docstatus, String erpStatus) {
    if (docstatus == 0) return 'Borrador';
    if (docstatus == 2 || erpStatus == 'Cancelled') return 'Cancelada';
    switch (erpStatus) {
      case 'To Bill':
        return 'Por facturar';
      case 'Partly Billed':
        return 'Parcialmente facturada';
      case 'Completed':
        return 'Completada';
      case 'Closed':
        return 'Cerrada';
      case 'Return':
        return 'Devolución';
      case 'Return Issued':
        return 'Devolución emitida';
      default:
        return erpStatus.isNotEmpty ? erpStatus : 'Enviada';
    }
  }

  /// Color según el estado real del ERP del Purchase Receipt.
  Color _erpStatusColor(int docstatus, String erpStatus) {
    if (docstatus == 0) return AppDesign.statusDraft;
    if (docstatus == 2 || erpStatus == 'Cancelled') {
      return AppDesign.statusCancelled;
    }
    switch (erpStatus) {
      case 'Completed':
        return AppDesign.statusSubmitted;
      case 'To Bill':
      case 'Partly Billed':
        return AppDesign.blueIcon;
      case 'Closed':
        return AppDesign.statusCancelled;
      case 'Return':
      case 'Return Issued':
        return AppDesign.orangeIcon;
      default:
        return AppDesign.statusSubmitted;
    }
  }

  // ════════════════════════════════════════════════════════════
  // ACCIÓN RÁPIDA DESDE LA LISTA
  // ════════════════════════════════════════════════════════════

  /// Factura la recepción completa desde la lista (sin abrir el detalle).
  Future<void> _facturarFromCard(BuildContext context, String name) async {
    final provider = context.read<MaterialReceiptProvider>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Facturar recepción'),
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
            child: const Text(
              'Facturar',
              style: TextStyle(color: AppDesign.statusSubmitted),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final fresh = await provider.createInvoiceForReceipt(name);
    if (!context.mounted) return;

    final ok = fresh != null;
    final newPct = ok
        ? ((fresh['per_billed'] is num)
              ? (fresh['per_billed'] as num).toDouble()
              : 100.0)
        : 0.0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '✅ Factura creada — recepción al ${newPct.toStringAsFixed(0)}% facturado'
              : '❌ ${provider.error}',
        ),
        backgroundColor: ok
            ? AppDesign.statusSubmitted
            : AppDesign.statusCancelled,
      ),
    );

    // Refrescar la lista para ver el nuevo estado
    await provider.fetchReceipts();
  }
}
