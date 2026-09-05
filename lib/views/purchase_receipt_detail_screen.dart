import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/erpnext_service.dart';

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
    if (docstatus == 0) return Colors.orange;
    if (docstatus == 1) return Colors.green;
    if (docstatus == 2) return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '📦 ${widget.prName}',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          IconButton(
            onPressed: _loadPR,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: Colors.red[700])),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadPR,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _buildDetail(),
    );
  }

  Widget _buildDetail() {
    final data = _prData!;
    final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
    final status = _statusText(data['docstatus']);
    final statusColor = _statusColor(data['docstatus']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Estado ───
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: statusColor.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  data['docstatus'] == 1
                      ? Icons.check_circle
                      : Icons.info_outline,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  status,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: statusColor,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.prName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ─── Info general ───
          _infoRow('Proveedor', data['supplier_name'] ?? data['supplier'] ?? '-'),
          _infoRow('Fecha', data['posting_date'] ?? '-'),
          _infoRow('Almacén', data['set_warehouse'] ?? '-'),
          if (data['cost_center'] != null && data['cost_center'].toString().isNotEmpty)
            _infoRow('Centro de Costos', data['cost_center']),
          _infoRow(
            'Total',
            NumberFormat('#,##0.00').format(data['grand_total'] ?? 0),
            isBold: true,
          ),

          const SizedBox(height: 16),

          // ─── Items ───
          Text(
            'Items (${items.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),

          ...items.map((item) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['item_name'] ?? item['item_code'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _pill('Código', item['item_code'] ?? '-'),
                          const SizedBox(width: 8),
                          _pill('Cantidad', '${item['qty'] ?? 0}'),
                          const SizedBox(width: 8),
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
              )),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
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
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}
