/// Modelo para una Entrada de Inventario (Stock Entry de ERPNext).
/// Tipos soportados por la app: Material Receipt, Material Transfer y
/// Material Issue — el tipo se elige de una lista traída del ERP
/// (doctype `Stock Entry Type`).
class StockEntry {
  String? id; // Nombre en ERPNext (ej: MAT-STE-2026-00001)
  String stockEntryType; // Material Receipt / Material Transfer / Material Issue
  String sourceWarehouse; // s_warehouse (Origen)
  String targetWarehouse; // t_warehouse (Destino)
  String costCenter; // Se pega en cada fila de items
  String remarks; // Observaciones
  String namingSeries;
  List<StockEntryItem> items;
  String status; // Borrador, Enviada, Cancelada (por docstatus, lógica interna)
  String erpStatus; // Estado REAL del ERP
  DateTime postingDate;
  DateTime createdAt;

  StockEntry({
    this.id,
    this.stockEntryType = '',
    this.sourceWarehouse = '',
    this.targetWarehouse = '',
    this.costCenter = '',
    this.remarks = '',
    this.namingSeries = '',
    List<StockEntryItem>? items,
    this.status = 'Borrador',
    this.erpStatus = '',
    DateTime? postingDate,
    DateTime? createdAt,
  })  : items = items ?? [],
        postingDate = postingDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  double get totalQty => items.fold(0.0, (sum, item) => sum + item.qty);

  /// Gran total (Material Receipt): Σ cantidad × precio base de cada fila.
  /// En Transfer/Issue el costo lo pone el ERP, así que este valor no aplica.
  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.qty * item.basicRate);

  /// Convierte a Map para enviar a ERPNext (Stock Entry).
  Map<String, dynamic> toMap() {
    return {
      'posting_date': postingDate.toIso8601String().substring(0, 10),
      'stock_entry_type': stockEntryType,
      if (sourceWarehouse.isNotEmpty) 'from_warehouse': sourceWarehouse,
      // Header del Stock Entry usa 'to_warehouse' (t_warehouse es de fila).
      if (targetWarehouse.isNotEmpty) 'to_warehouse': targetWarehouse,
      if (namingSeries.isNotEmpty) 'naming_series': namingSeries,
      if (remarks.isNotEmpty) 'remarks': remarks,
      if (costCenter.isNotEmpty) 'cost_center': costCenter,
      'items': items.map((item) => item.toMap(costCenter: costCenter)).toList(),
    };
  }

  /// Crea desde un Map de ERPNext (Stock Entry).
  factory StockEntry.fromErp(Map<String, dynamic> data) {
    final items = <StockEntryItem>[];
    if (data['items'] != null) {
      for (final item in data['items']) {
        items.add(StockEntryItem.fromErp(item));
      }
    }

    return StockEntry(
      id: data['name'],
      stockEntryType: (data['stock_entry_type'] ?? '').toString(),
      sourceWarehouse:
          (data['from_warehouse'] ?? data['to_warehouse'] ?? '').toString(),
      targetWarehouse:
          (data['to_warehouse'] ?? data['t_warehouse'] ?? '').toString(),
      costCenter: (data['cost_center'] ?? '').toString(),
      remarks: (data['remarks'] ?? '').toString(),
      namingSeries: (data['naming_series'] ?? '').toString(),
      items: items,
      status: _statusFromDocstatus(data['docstatus']),
      erpStatus: (data['status'] ?? '').toString(),
      postingDate:
          DateTime.tryParse(data['posting_date'] ?? '') ?? DateTime.now(),
    );
  }

  static String _statusFromDocstatus(dynamic docstatus) {
    if (docstatus == 0) return 'Borrador';
    if (docstatus == 1) return 'Enviada';
    if (docstatus == 2) return 'Cancelada';
    return 'Borrador';
  }
}

/// Modelo para un item dentro de una Entrada de Inventario (Stock Entry).
/// En Material Transfer el item lleva s_warehouse Y t_warehouse propios.
class StockEntryItem {
  String itemCode;
  String itemName;
  double qty;
  String uom;
  String sourceWarehouse; // s_warehouse de la fila
  String targetWarehouse; // t_warehouse de la fila
  double basicRate; // basic_rate (el ERP lo completa con el costo si va 0)

  StockEntryItem({
    required this.itemCode,
    this.itemName = '',
    this.qty = 1,
    this.uom = '',
    this.sourceWarehouse = '',
    this.targetWarehouse = '',
    this.basicRate = 0.0,
  });

  Map<String, dynamic> toMap({String costCenter = ''}) {
    return {
      'item_code': itemCode,
      'qty': qty,
      if (sourceWarehouse.isNotEmpty) 's_warehouse': sourceWarehouse,
      if (targetWarehouse.isNotEmpty) 't_warehouse': targetWarehouse,
      if (costCenter.isNotEmpty) 'cost_center': costCenter,
      // El precio base solo se manda si el usuario lo definió (Material
      // Receipt); en Transfer/Issue el ERP lo calcula con el costo del item.
      if (basicRate > 0) 'basic_rate': basicRate,
      // La UOM solo se manda si es real; 'Unidad' es placeholder y NO existe
      // en el ERP (la real es 'Unidad(es)'). Sin UOM el ERP rellena
      // stock_uom del item solo.
      if (uom.isNotEmpty && uom != 'Unidad') 'uom': uom,
    };
  }

  factory StockEntryItem.fromErp(Map<String, dynamic> data) {
    return StockEntryItem(
      itemCode: data['item_code'] ?? '',
      itemName: data['item_name'] ?? '',
      qty: (data['qty'] ?? 0).toDouble(),
      uom: data['uom'] ?? '',
      sourceWarehouse: data['s_warehouse'] ?? '',
      targetWarehouse: data['t_warehouse'] ?? '',
      basicRate: (data['basic_rate'] ?? 0).toDouble(),
    );
  }
}
