/// Modelo para una Orden de Compra local (antes de enviar a ERPNext).
class PurchaseOrder {
  String? id; // Nombre en ERPNext (ej: PO-00001)
  String supplier; // Nombre del proveedor (display)
  String supplierId; // ID en ERPNext (ej: PRO00013)
  DateTime scheduleDate;
  String costCenter; // Centro de costos
  String setWarehouse; // Almacén destino
  List<PurchaseOrderItem> items;
  String status; // Borrador, Enviada, Cancelada
  double grandTotal;
  DateTime createdAt;
  String namingSeries; // Serie de numeración (ej: PO-.YYYY.-)

  PurchaseOrder({
    this.id,
    required this.supplier,
    this.supplierId = '',
    required this.scheduleDate,
    this.costCenter = '',
    this.setWarehouse = '',
    List<PurchaseOrderItem>? items,
    this.status = 'Borrador',
    this.grandTotal = 0.0,
    DateTime? createdAt,
    this.namingSeries = '',
  })  : items = items ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// Calcula el total de la orden.
  double get total => items.fold(0.0, (sum, item) => sum + item.total);

  /// Cantidad total de items.
  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);

  /// Convierte a Map para enviar a ERPNext.
  Map<String, dynamic> toMap() {
    return {
      'supplier': supplierId.isNotEmpty ? supplierId : supplier,
      'schedule_date': scheduleDate.toIso8601String().substring(0, 10),
      'cost_center': costCenter,
      'set_warehouse': setWarehouse,
      'items': items.map((item) => item.toMap()).toList(),
    };
  }

  /// Crea desde un Map de ERPNext.
  factory PurchaseOrder.fromErp(Map<String, dynamic> data) {
    final items = <PurchaseOrderItem>[];
    if (data['items'] != null) {
      for (final item in data['items']) {
        items.add(PurchaseOrderItem.fromErp(item));
      }
    }

    return PurchaseOrder(
      id: data['name'],
      supplier: data['supplier_name'] ?? data['supplier'] ?? '',
      supplierId: data['supplier'] ?? '',
      scheduleDate: DateTime.tryParse(data['schedule_date'] ?? '') ?? DateTime.now(),
      costCenter: data['cost_center'] ?? '',
      setWarehouse: data['set_warehouse'] ?? '',
      items: items,
      status: _statusFromDocstatus(data['docstatus']),
      grandTotal: (data['grand_total'] ?? 0).toDouble(),
    );
  }

  static String _statusFromDocstatus(dynamic docstatus) {
    if (docstatus == 0) return 'Borrador';
    if (docstatus == 1) return 'Enviada';
    if (docstatus == 2) return 'Cancelada';
    return 'Borrador';
  }
}

/// Modelo para un item dentro de una Orden de Compra.
class PurchaseOrderItem {
  String itemCode;
  String itemName;
  int qty;
  double rate;

  PurchaseOrderItem({
    required this.itemCode,
    this.itemName = '',
    this.qty = 1,
    this.rate = 0.0,
  });

  double get total => qty * rate;

  Map<String, dynamic> toMap() {
    return {
      'item_code': itemCode,
      'qty': qty,
      'rate': rate,
    };
  }

  factory PurchaseOrderItem.fromErp(Map<String, dynamic> data) {
    return PurchaseOrderItem(
      itemCode: data['item_code'] ?? '',
      itemName: data['item_name'] ?? '',
      qty: (data['qty'] ?? 0).toInt(),
      rate: (data['rate'] ?? 0).toDouble(),
    );
  }
}
