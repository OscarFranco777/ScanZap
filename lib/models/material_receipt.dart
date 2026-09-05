/// Modelo para una Recepción de Mercadería (Stock Entry type Material Receipt).
class MaterialReceipt {
  String? id; // Nombre en ERPNext (ej: MAT-REC-00001)
  String warehouse;
  String supplier;
  String stockEntryType;
  List<MaterialReceiptItem> items;
  String status; // Borrador, Enviada, Cancelada
  double totalAmount;
  DateTime postingDate;
  DateTime createdAt;

  MaterialReceipt({
    this.id,
    this.warehouse = '',
    this.supplier = '',
    this.stockEntryType = 'Material Receipt',
    List<MaterialReceiptItem>? items,
    this.status = 'Borrador',
    this.totalAmount = 0.0,
    DateTime? postingDate,
    DateTime? createdAt,
  })  : items = items ?? [],
        postingDate = postingDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);

  /// Convierte a Map para enviar a ERPNext.
  Map<String, dynamic> toMap() {
    return {
      'stock_entry_type': stockEntryType,
      'posting_date': postingDate.toIso8601String().substring(0, 10),
      if (supplier.isNotEmpty) 'supplier': supplier,
      'items': items.map((item) => item.toMap()).toList(),
    };
  }

  /// Crea desde un Map de ERPNext.
  factory MaterialReceipt.fromErp(Map<String, dynamic> data) {
    final items = <MaterialReceiptItem>[];
    if (data['items'] != null) {
      for (final item in data['items']) {
        items.add(MaterialReceiptItem.fromErp(item));
      }
    }

    return MaterialReceipt(
      id: data['name'],
      warehouse: data['items']?.isNotEmpty == true
          ? (data['items'][0]['t_warehouse'] ?? '')
          : '',
      supplier: data['supplier'] ?? '',
      stockEntryType: data['stock_entry_type'] ?? 'Material Receipt',
      items: items,
      status: _statusFromDocstatus(data['docstatus']),
      totalAmount: (data['total_amount'] ?? 0).toDouble(),
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

  Map<String, dynamic> toMap() {
    return {
      'item_code': itemCode,
      'qty': qty,
      't_warehouse': warehouse,
      'uom': uom,
    };
  }

  factory MaterialReceiptItem.fromErp(Map<String, dynamic> data) {
    return MaterialReceiptItem(
      itemCode: data['item_code'] ?? '',
      itemName: data['item_name'] ?? '',
      qty: (data['qty'] ?? 0).toInt(),
      uom: data['uom'] ?? 'Unidad',
      warehouse: data['t_warehouse'] ?? '',
    );
  }
}
