/// Modelo para una Factura de Compra (Purchase Invoice).
/// Orígenes soportados: creación directa, desde una Purchase Order (sin
/// recepción previa → update_stock = true) y desde un Purchase Receipt
/// (el stock ya lo actualizó la recepción → update_stock = false).
class PurchaseInvoice {
  String? id; // Nombre en ERPNext (ej: ACC-PINV-2026-00045)
  String supplier; // Nombre visible del proveedor
  String supplierId; // ID en ERPNext del proveedor
  String billNo; // Nº de factura del proveedor (bill_no)
  String purchaseOrder; // PO vinculada (si existe)
  String purchaseReceipt; // PR vinculada (si existe)
  String namingSeries;
  String warehouse;
  String costCenter;
  bool updateStock; // Tilde "Actualizar inventario" del ERP
  List<PurchaseInvoiceItem> items;
  String status; // Borrador, Enviada, Cancelada (por docstatus, lógica interna)
  String erpStatus; // Estado REAL del ERP (Draft, Paid, Overdue, ...)
  double totalAmount;
  double netTotal; // net_total del ERP (cuando el doc ya existe)
  double taxesTotal; // total_taxes_and_charges del ERP
  DateTime postingDate;
  DateTime createdAt;

  PurchaseInvoice({
    this.id,
    this.supplier = '',
    this.supplierId = '',
    this.billNo = '',
    this.purchaseOrder = '',
    this.purchaseReceipt = '',
    this.namingSeries = '',
    this.warehouse = '',
    this.costCenter = '',
    this.updateStock = true,
    List<PurchaseInvoiceItem>? items,
    this.status = 'Borrador',
    this.erpStatus = '',
    this.totalAmount = 0.0,
    this.netTotal = 0.0,
    this.taxesTotal = 0.0,
    DateTime? postingDate,
    DateTime? createdAt,
  })  : items = items ?? [],
        postingDate = postingDate ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  double get totalQty => items.fold(0.0, (sum, item) => sum + item.qty);

  /// Subtotal en vivo (Σ qty × rate) — se recalcula al editar items.
  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.qty * item.rate);

  /// Convierte a Map para enviar a ERPNext (Purchase Invoice).
  Map<String, dynamic> toMap() {
    return {
      'posting_date': postingDate.toIso8601String().substring(0, 10),
      if (supplierId.isNotEmpty) 'supplier': supplierId,
      if (supplier.isEmpty && supplierId.isEmpty) 'supplier': '',
      if (billNo.isNotEmpty) 'bill_no': billNo,
      if (namingSeries.isNotEmpty) 'naming_series': namingSeries,
      if (warehouse.isNotEmpty) 'set_warehouse': warehouse,
      if (costCenter.isNotEmpty) 'cost_center': costCenter,
      'update_stock': updateStock,
      'items': items
          .map(
            (item) => item.toMap(
              purchaseOrder: purchaseOrder,
              purchaseReceipt: purchaseReceipt,
            ),
          )
          .toList(),
    };
  }

  /// Crea desde un Map de ERPNext (Purchase Invoice).
  factory PurchaseInvoice.fromErp(Map<String, dynamic> data) {
    final items = <PurchaseInvoiceItem>[];
    if (data['items'] != null) {
      for (final item in data['items']) {
        items.add(PurchaseInvoiceItem.fromErp(item));
      }
    }

    final warehouse = items.isNotEmpty
        ? (items.first.warehouse.isNotEmpty
            ? items.first.warehouse
            : (data['set_warehouse'] ?? ''))
        : (data['set_warehouse'] ?? '');

    // Detectar vínculos desde los items
    String po = '';
    String pr = '';
    if (data['items'] != null && (data['items'] as List).isNotEmpty) {
      po = data['items'][0]['purchase_order'] ?? '';
      pr = data['items'][0]['purchase_receipt'] ?? '';
    }

    final total = data['grand_total'] ?? 0;

    return PurchaseInvoice(
      id: data['name'],
      supplier: data['supplier'] ?? '',
      supplierId: data['supplier'] ?? '',
      billNo: (data['bill_no'] ?? '').toString(),
      purchaseOrder: po,
      purchaseReceipt: pr,
      namingSeries: data['naming_series'] ?? '',
      warehouse: warehouse.toString(),
      costCenter: data['cost_center'] ?? '',
      updateStock: data['update_stock'] == 1 || data['update_stock'] == true,
      items: items,
      status: _statusFromDocstatus(data['docstatus']),
      erpStatus: (data['status'] ?? '').toString(),
      totalAmount: (total is num) ? total.toDouble() : 0.0,
      netTotal: (data['net_total'] is num)
          ? (data['net_total'] as num).toDouble()
          : 0.0,
      taxesTotal: (data['total_taxes_and_charges'] is num)
          ? (data['total_taxes_and_charges'] as num).toDouble()
          : 0.0,
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

/// Modelo para un item dentro de una Factura de Compra.
class PurchaseInvoiceItem {
  String itemCode;
  String itemName;
  double qty;
  String uom;
  String warehouse;
  double rate; // Precio de compra unitario
  String purchaseOrderItem; // ID del ítem en la PO (po_detail)
  String purchaseReceiptItem; // ID del ítem en el PR (pr_detail)

  PurchaseInvoiceItem({
    required this.itemCode,
    this.itemName = '',
    this.qty = 1,
    this.uom = '',
    this.warehouse = '',
    this.rate = 0.0,
    this.purchaseOrderItem = '',
    this.purchaseReceiptItem = '',
  });

  Map<String, dynamic> toMap({
    String purchaseOrder = '',
    String purchaseReceipt = '',
  }) {
    return {
      'item_code': itemCode,
      'qty': qty,
      'rate': rate,
      'warehouse': warehouse,
      // La UOM solo se manda si es real; 'Unidad' es placeholder y no
      // existe en el ERP (la real es 'Unidad(es)'). Sin UOM el ERP
      // rellena stock_uom del item solo.
      if (uom.isNotEmpty && uom != 'Unidad') 'uom': uom,
      if (purchaseOrder.isNotEmpty) 'purchase_order': purchaseOrder,
      if (purchaseOrderItem.isNotEmpty) 'po_detail': purchaseOrderItem,
      if (purchaseReceipt.isNotEmpty) 'purchase_receipt': purchaseReceipt,
      if (purchaseReceiptItem.isNotEmpty) 'pr_detail': purchaseReceiptItem,
    };
  }

  factory PurchaseInvoiceItem.fromErp(Map<String, dynamic> data) {
    return PurchaseInvoiceItem(
      itemCode: data['item_code'] ?? '',
      itemName: data['item_name'] ?? '',
      qty: (data['qty'] ?? 0).toDouble(),
      uom: data['uom'] ?? '',
      warehouse: data['warehouse'] ?? '',
      rate: (data['rate'] ?? 0).toDouble(),
      purchaseOrderItem: data['purchase_order_item'] ?? data['po_detail'] ?? '',
      purchaseReceiptItem: data['purchase_receipt_item'] ?? data['pr_detail'] ?? '',
    );
  }
}
