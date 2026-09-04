/// Modelo que representa un Item (producto) traído de ERPNext.
/// Mapea los campos relevantes de la API REST de Frappe/ERPNext.
/// Los barcodes se obtienen del item_code directamente (en esta instancia,
/// barcode siempre coincide con item_code).
class ItemModel {
  final String name;       // ID interno de Frappe (ej: "AB-001")
  final String itemCode;   // Código de barras / Item Code
  final String itemName;   // Nombre descriptivo del producto
  final String stockUom;   // Unidad de medida (Pieza, Kg, Litro, etc.)
  final String barcode;    // Barcode directo del campo Item.barcode (puede estar vacío)

  ItemModel({
    required this.name,
    required this.itemCode,
    required this.itemName,
    required this.stockUom,
    this.barcode = '',
  });

  /// Factory: construye un ItemModel desde el JSON que devuelve ERPNext.
  /// La API devuelve {"name": "...", "item_code": "...", ...}
  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      name: json['name'] ?? '',
      itemCode: json['item_code'] ?? '',
      itemName: json['item_name'] ?? '',
      stockUom: json['stock_uom'] ?? 'Unidad',
      barcode: json['barcode'] ?? '',
    );
  }

  /// Búsqueda: compara código de barras/item_code de forma case-insensitive.
  bool matchesCode(String query) {
    final q = query.trim().toLowerCase();
    return itemCode.toLowerCase() == q || name.toLowerCase() == q;
  }

  @override
  String toString() => 'ItemModel($itemCode - $itemName)';
}
