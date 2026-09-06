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
  String status; // Borrador, Enviada, Cancelada
  double totalAmount;
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
    this.totalAmount = 0.0,
    DateTime? postingDate,
    DateTime? createdAt,
  })  : items = items ?? [],
        postingDate = postingDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);

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
      totalAmount: (total is num) ? total.toDouble() : 0.0,
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
  int qty;
  String uom;
  String warehouse;

  MaterialReceiptItem({
    required this.itemCode,
    this.itemName = '',
    this.qty = 1,
    this.uom = 'Unidad',
    this.warehouse = '',
  });

  Map<String, dynamic> toMap({String purchaseOrder = ''}) {
    return {
      'item_code': itemCode,
      'qty': qty,
      'warehouse': warehouse,
      'uom': uom,
      if (purchaseOrder.isNotEmpty) 'purchase_order': purchaseOrder,
    };
  }

  factory MaterialReceiptItem.fromErp(Map<String, dynamic> data) {
    return MaterialReceiptItem(
      itemCode: data['item_code'] ?? '',
      itemName: data['item_name'] ?? '',
      qty: (data['qty'] ?? 0).toInt(),
      uom: data['uom'] ?? 'Unidad',
      warehouse: data['warehouse'] ?? '',
    );
  }
}
