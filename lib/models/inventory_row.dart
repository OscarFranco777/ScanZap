/// Modelo que representa una fila de inventario en la sesión de conteo.
/// Cada vez que se escanea un producto, se crea o actualiza una fila.
class InventoryRow {
  final String itemCode;      // Código interno del producto (item_code de ERPNext)
  final String displayCode;   // Código para mostrar (barcode original con ceros)
  String itemName;            // Nombre del producto (de ERPNext)
  String stockUom;            // Unidad de medida
  double quantity;            // Cantidad contada (escaneada, admite decimales si la UOM lo permite)
  double unitCost;            // Costo unitario (del Excel)
  bool hasCost;               // Si se encontró costo en el Excel
  DateTime scannedAt;         // Cuándo se escaneó por primera vez

  InventoryRow({
    required this.itemCode,
    required this.itemName,
    required this.stockUom,
    String? displayCode,
    this.quantity = 1,
    this.unitCost = 0.0,
    this.hasCost = true,
    DateTime? scannedAt,
  }) : displayCode = displayCode ?? itemCode,
       scannedAt = scannedAt ?? DateTime.now();

  /// Costo total de esta línea = cantidad × costo unitario
  double get totalCost => quantity * unitCost;

  /// Incrementa la cantidad (cuando se vuelve a escanear)
  void increment({double step = 1}) {
    quantity += step;
  }

  /// Decrementa la cantidad (botón -), mínimo 0
  void decrement({double step = 1}) {
    final newQty = quantity - step;
    quantity = newQty < 0 ? 0 : newQty;
  }

  /// Suma N unidades (escaneo con cantidad personalizada)
  void addQuantity(double qty) {
    quantity += qty < 0 ? 0 : qty;
  }

  /// Actualiza la cantidad directamente (entrada manual)
  void setQuantity(double qty) {
    quantity = qty < 0 ? 0 : qty;
  }

  Map<String, dynamic> toMap() {
    return {
      'item_code': itemCode,
      'display_code': displayCode,
      'item_name': itemName,
      'stock_uom': stockUom,
      'quantity': quantity,
      'unit_cost': unitCost,
      'total_cost': totalCost,
      'has_cost': hasCost,
      'scanned_at': scannedAt.toIso8601String(),
    };
  }
}
