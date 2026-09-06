import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/erpnext_service.dart';
import '../theme/app_design.dart';

/// Pantalla de detalle de una Purchase Receipt existente en ERPNext.
/// Muestra los datos de la PR recibida por nombre.
class PurchaseReceiptDetailScreen extends StatefulWidget {
  final String prName;
  final ErpNextService erpNextService;

  const PurchaseReceiptDetailScreen({
    super.key,
    required this.prName,
    required this.erpNextService,
  });

  @override
  State<PurchaseReceiptDetailScreen> createState() =>
      _PurchaseReceiptDetailScreenState();
}

class _PurchaseReceiptDetailScreenState
    extends State<PurchaseReceiptDetailScreen> {
  Map<String, dynamic>? _prData;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPR();
  }

  Future<void> _loadPR() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.erpNextService.getPurchaseReceipt(widget.prName);
      if (data != null) {
        setState(() {
          _prData = data;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'No se pudo cargar la recepción';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  String _statusText(dynamic docstatus) {
    if (docstatus == 0) return 'Borrador';
    if (docstatus == 1) return 'Recibida';
    if (docstatus == 2) return 'Cancelada';
    return 'Desconocido';
  }

  Color _statusColor(dynamic docstatus) {
    if (docstatus == 0) return AppDesign.statusDraft;
    if (docstatus == 1) return AppDesign.statusSubmitted;
    if (docstatus == 2) return AppDesign.statusCancelled;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── Header navy ───
          AppDesign.buildHeader(
            title: '📦 ${widget.prName}',
            subtitle: _loading
                ? 'Cargando...'
                : _prData != null
                    ? _statusText(_prData!['docstatus'])
                    : 'Detalle de recepción',
            icon: Icons.local_shipping_outlined,
            onBack: () => Navigator.pop(context),
            actions: [
              GestureDetector(
                onTap: _loadPR,
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

          // ─── Body ───
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : _buildDetail(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return AppDesign.emptyState(
      icon: Icons.error_outline,
      title: _error!,
      subtitle: 'Tocá para reintentar',
    );
  }

  Widget _buildDetail() {
    final data = _prData!;
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final docstatus = data['docstatus'];
    final status = _statusText(docstatus);
    final statusColor = _statusColor(docstatus);

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 12),

          // ─── Status card ───
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                AppDesign.circleAvatar(
                  icon: docstatus == 1
                      ? Icons.check_circle
                      : Icons.info_outline,
                  bgColor: statusColor.withValues(alpha: 0.12),
                  iconColor: statusColor,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        widget.prName,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                AppDesign.statusBadge(status, statusColor),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─── Info general ───
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.navy.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppDesign.circleAvatar(
                      icon: Icons.business_outlined,
                      bgColor: AppDesign.blueLight,
                      iconColor: AppDesign.blueIcon,
                      size: 32,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Información General',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppDesign.navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow('Proveedor', data['supplier_name'] ?? data['supplier'] ?? '-'),
                _infoRow('Fecha', data['posting_date'] ?? '-'),
                _infoRow('Almacén', data['set_warehouse'] ?? '-'),
                if (data['cost_center'] != null && data['cost_center'].toString().isNotEmpty)
                  _infoRow('Centro de Costos', data['cost_center']),
                _infoRow(
                  'Total',
                  'L ${NumberFormat('#,##0.00').format(data['grand_total'] ?? 0)}',
                  isBold: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Sección Items ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 16, color: AppDesign.navy),
                const SizedBox(width: 6),
                Text(
                  'ITEMS (${items.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppDesign.navy,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ─── Lista de items ───
          if (items.isEmpty)
            AppDesign.emptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No hay items',
            )
          else
            ...items.map((item) => _buildItemCard(item)),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    return AppDesign.buildListCard(
      context: context,
      child: Row(
        children: [
          AppDesign.circleAvatar(
            icon: Icons.inventory_2_outlined,
            bgColor: AppDesign.tealLight,
            iconColor: AppDesign.tealIcon,
            size: 36,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['item_name'] ?? item['item_code'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppDesign.navy,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _pill('Código', '${item['item_code'] ?? '-'}'),
                    _pill('Cantidad', '${item['qty'] ?? 0}'),
                    _pill('Recibido', '${item['received_qty'] ?? 0}'),
                  ],
                ),
                if (item['purchase_order'] != null &&
                    item['purchase_order'].toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'PO: ${item['purchase_order']}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
                color: isBold ? AppDesign.navy : Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppDesign.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppDesign.navy,
        ),
      ),
    );
  }
}
