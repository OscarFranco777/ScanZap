/// Modelo para una Recepción de Mercadería (Stock Entry type Material Receipt).
class MaterialReceipt {
  String? id; // Nombre en ERPNext (ej: MAT-PRE-2026-00173)
  String warehouse;
  String supplier; // Nombre visible del proveedor
  String supplierId; // ID en ERPNext del proveedor
  String purchaseOrder; // PO vinculada (si existe)
  String namingSeries;
  String costCenter;
  List<MaterialReceiptItem> items;
  String status; // Borrador, Enviada, Cancelada (por docstatus, lógica interna)
  String erpStatus; // Estado REAL del ERP (To Bill, Partly Billed, Completed...)
  double perBilled; // % facturado según el ERP
  double totalAmount;
  double netTotal; // net_total del ERP (cuando el doc ya existe)
  double taxesTotal; // total_taxes_and_charges del ERP
  DateTime postingDate;
  DateTime createdAt;

  MaterialReceipt({
    this.id,
    this.warehouse = '',
    this.supplier = '',
    this.supplierId = '',
    this.purchaseOrder = '',
    this.namingSeries = '',
    this.costCenter = '',
    List<MaterialReceiptItem>? items,
    this.status = 'Borrador',
    this.erpStatus = '',
    this.perBilled = 0.0,
    this.totalAmount = 0.0,
    this.netTotal = 0.0,
    this.taxesTotal = 0.0,
    DateTime? postingDate,
    DateTime? createdAt,
  })  : items = items ?? [],
        postingDate = postingDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  double get totalQty => items.fold(0.0, (sum, item) => sum + item.qty);

  /// Subtotal en vivo: Σ (monto neto del item, o qty × precio de lista
  /// si aún no hay monto). Se recalcula al editar items.
  double get subtotal => items.fold(
      0.0,
      (sum, item) =>
          sum +
          (item.netAmount > 0 ? item.netAmount : item.qty * item.priceListRate));

  /// Convierte a Map para enviar a ERPNext (Purchase Receipt).
  Map<String, dynamic> toMap() {
    return {
      'posting_date': postingDate.toIso8601String().substring(0, 10),
      if (supplierId.isNotEmpty) 'supplier': supplierId,
      if (warehouse.isNotEmpty) 'set_warehouse': warehouse,
      if (namingSeries.isNotEmpty) 'naming_series': namingSeries,
      if (costCenter.isNotEmpty) 'cost_center': costCenter,
      'items': items.map((item) => item.toMap(purchaseOrder: purchaseOrder)).toList(),
    };
  }

  /// Crea desde un Map de ERPNext (Purchase Receipt).
  factory MaterialReceipt.fromErp(Map<String, dynamic> data) {
    final items = <MaterialReceiptItem>[];
    if (data['items'] != null) {
      for (final item in data['items']) {
        items.add(MaterialReceiptItem.fromErp(item));
      }
    }

    // Determinar almacén desde los items o el campo set_warehouse
    final warehouse = items.isNotEmpty
        ? (items.first.warehouse.isNotEmpty
            ? items.first.warehouse
            : (data['set_warehouse'] ?? ''))
        : (data['set_warehouse'] ?? '');

    // Detectar PO vinculada desde los items
    String po = '';
    if (data['items'] != null && (data['items'] as List).isNotEmpty) {
      po = data['items'][0]['purchase_order'] ?? '';
    }

    final total = data['grand_total'] ?? 0;

    return MaterialReceipt(
      id: data['name'],
      warehouse: warehouse.toString(),
      supplier: data['supplier'] ?? '',
      supplierId: data['supplier'] ?? '',
      purchaseOrder: po,
      namingSeries: data['naming_series'] ?? '',
      costCenter: data['cost_center'] ?? '',
      items: items,
      status: _statusFromDocstatus(data['docstatus']),
      erpStatus: (data['status'] ?? '').toString(),
      perBilled: (data['per_billed'] is num) ? (data['per_billed'] as num).toDouble() : 0.0,
      totalAmount: (total is num) ? total.toDouble() : 0.0,
      netTotal: (data['net_total'] is num)
          ? (data['net_total'] as num).toDouble()
          : 0.0,
      taxesTotal: (data['total_taxes_and_charges'] is num)
          ? (data['total_taxes_and_charges'] as num).toDouble()
          : 0.0,
      postingDate: DateTime.tryParse(data['posting_date'] ?? '') ?? DateTime.now(),
    );
  }

  static String _statusFromDocstatus(dynamic docstatus) {
    if (docstatus == 0) return 'Borrador';
    if (docstatus == 1) return 'Enviada';
    if (docstatus == 2) return 'Cancelada';
    return 'Borrador';
  }
}

/// Modelo para un item dentro de una Recepción de Mercadería.
class MaterialReceiptItem {
  String itemCode;
  String itemName;
  double qty;
  String uom;
  String warehouse;
  String purchaseOrderItem; // ID del ítem en la PO (para vinculación)
  double priceListRate; // Precio de lista (desde la PO)
  double netAmount;     // Monto neto (desde la PO)

  MaterialReceiptItem({
    required this.itemCode,
    this.itemName = '',
    this.qty = 1,
    this.uom = '',
    this.warehouse = '',
    this.purchaseOrderItem = '',
    this.priceListRate = 0.0,
    this.netAmount = 0.0,
  });

  Map<String, dynamic> toMap({String purchaseOrder = ''}) {
    return {
      'item_code': itemCode,
      'qty': qty,
      'warehouse': warehouse,
      // La UOM solo se manda si es real; 'Unidad' es placeholder y no
      // existe en el ERP (la real es 'Unidad(es)'). Sin UOM el ERP
      // rellena stock_uom del item solo.
      if (uom.isNotEmpty && uom != 'Unidad') 'uom': uom,
      if (purchaseOrder.isNotEmpty) 'purchase_order': purchaseOrder,
      if (purchaseOrderItem.isNotEmpty)
        'purchase_order_item': purchaseOrderItem,
      if (priceListRate > 0) 'price_list_rate': priceListRate,
      if (netAmount > 0) 'net_amount': netAmount,
    };
  }

  factory MaterialReceiptItem.fromErp(Map<String, dynamic> data) {
    return MaterialReceiptItem(
      itemCode: data['item_code'] ?? '',
      itemName: data['item_name'] ?? '',
      qty: (data['qty'] ?? 0).toDouble(),
      uom: data['uom'] ?? '',
      warehouse: data['warehouse'] ?? '',
      purchaseOrderItem: data['purchase_order_item'] ?? '',
      priceListRate: (data['price_list_rate'] ?? 0).toDouble(),
      netAmount: (data['net_amount'] ?? 0).toDouble(),
    );
  }
}
