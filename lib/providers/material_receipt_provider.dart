import 'package:flutter/material.dart';
import '../models/material_receipt.dart';
import '../models/item_model.dart';
import '../services/erpnext_service.dart';

/// Estado del módulo de Recepción de Mercadería.
class MaterialReceiptProvider with ChangeNotifier {
  final ErpNextService erpNextService;

  // ─── Estado ───
  bool isLoading = false;
  String error = '';

  // ─── Estado del guardado ───
  bool isSaved = false;
  bool isSubmitted = false;

  // ─── Loading para creación desde PO ───
  bool _loadingReceipt = false;
  bool get loadingReceipt => _loadingReceipt;

  // ─── Recepción actual (en edición) ───
  MaterialReceipt? currentReceipt;

  // ─── Lista de recepciones ───
  List<Map<String, dynamic>> receiptsList = [];

  // ─── Purchase Orders enviadas (para crear desde PO) ───
  List<Map<String, dynamic>> submittedPOs = [];

  // ─── Items cacheados del inventario ───
  Map<String, ItemModel> itemsByCode = {};

  // ─── Almacenes ───
  List<Map<String, dynamic>> warehouses = [];

  // ─── Centros de costo ───
  List<Map<String, dynamic>> costCenters = [];

  // ─── Naming series ───
  List<String> namingSeriesOptions = [];
  bool catalogsLoaded = false;

  // ─── Último escaneo ───
  String lastScannedCode = '';
  String lastScanMessage = '';
  bool lastScanWasError = false;

  MaterialReceiptProvider({required this.erpNextService});

  /// Carga la caché de items desde el provider principal.
  void loadItemsCache(Map<String, ItemModel> cache) {
    itemsByCode = cache;
  }

  // ══════════════════════════════════════════════════════════════
  // RECEPCIONES
  // ══════════════════════════════════════════════════════════════

  /// Lista recepciones de mercadería desde ERPNext.
  Future<void> fetchReceipts() async {
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      receiptsList = await erpNextService.listMaterialReceipts();
    } catch (e) {
      error = 'Error cargando recepciones: $e';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Carga catálogos (almacenes, naming series PR, centros de costo) desde ERPNext.
  Future<void> fetchCatalogs() async {
    try {
      final results = await Future.wait([
        erpNextService.fetchWarehouses(),
        erpNextService.fetchPurchaseReceiptNamingSeries(),
        erpNextService.fetchCostCenters(),
      ]);
      warehouses = List<Map<String, dynamic>>.from(results[0] as List);
      namingSeriesOptions = List<String>.from(results[1] as List);
      costCenters = List<Map<String, dynamic>>.from(results[2] as List);
      catalogsLoaded = true;
    } catch (e) {
      print('[MR] Error cargando catálogos: $e');
    }
    notifyListeners();
  }

  /// Busca proveedores por nombre.
  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    return await erpNextService.searchSuppliers(query);
  }

  /// Carga Purchase Orders enviadas para crear recepción desde PO.
  Future<void> fetchSubmittedPOs() async {
    try {
      submittedPOs = await erpNextService.listSubmittedPurchaseOrders();
    } catch (e) {
      print('[MR] Error cargando POs enviadas: $e');
    }
    notifyListeners();
  }

  /// Crea una recepción local (borrador).
  void createNewReceipt({
    String warehouse = '',
    String supplier = '',
    String supplierId = '',
    String purchaseOrder = '',
    String namingSeries = '',
    String costCenter = '',
    DateTime? postingDate,
  }) {
    currentReceipt = MaterialReceipt(
      warehouse: warehouse,
      supplier: supplier,
      supplierId: supplierId,
      purchaseOrder: purchaseOrder,
      namingSeries: namingSeries,
      costCenter: costCenter,
      postingDate: postingDate ?? DateTime.now(),
    );
    isSaved = false;
    isSubmitted = false;
    notifyListeners();
  }

  /// Crea una recepción desde los items de una Purchase Order enviada.
  Future<void> createFromPO(String poName, {String warehouse = '', String supplier = '', String supplierId = '', String namingSeries = '', String costCenter = ''}) async {
    _loadingReceipt = true;
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final items = await erpNextService.getPurchaseOrderItems(poName);

      final receiptItems = items.map((item) {
        return MaterialReceiptItem(
          itemCode: item['item_code'] ?? '',
          itemName: item['item_name'] ?? '',
          qty: (item['qty'] ?? 1).toInt(),
          uom: item['uom'] ?? 'Unidad',
          warehouse: warehouse.isNotEmpty ? warehouse : (item['warehouse'] ?? ''),
        );
      }).toList();

      // Si no se pasó warehouse, tomar del primer item
      final effectiveWarehouse = warehouse.isNotEmpty
          ? warehouse
          : (receiptItems.isNotEmpty ? receiptItems.first.warehouse : '');

      currentReceipt = MaterialReceipt(
        warehouse: effectiveWarehouse,
        supplier: supplier,
        supplierId: supplierId.isNotEmpty ? supplierId : supplier,
        purchaseOrder: poName,
        namingSeries: namingSeries,
        costCenter: costCenter,
        items: receiptItems,
      );
    } catch (e) {
      error = 'Error cargando items de PO: $e';
    }

    _loadingReceipt = false;
    isLoading = false;
    notifyListeners();
  }

  /// Carga una recepción existente desde ERPNext.
  Future<void> loadReceipt(String name) async {
    _loadingReceipt = true;
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      // Purchase Receipt (el único tipo que usamos)
      final data = await erpNextService.getPurchaseReceipt(name);

      if (data != null) {
        currentReceipt = MaterialReceipt.fromErp(data);
        isSaved = currentReceipt!.id != null;
        isSubmitted = currentReceipt!.status == 'Enviada';
      } else {
        error = 'Recepción no encontrada';
      }
    } catch (e) {
      error = 'Error cargando recepción: $e';
    }

    _loadingReceipt = false;
    isLoading = false;
    notifyListeners();
  }

  /// Agrega un item escaneado a la recepción actual.
  Future<bool> scanItemToReceipt(String code, {int quantity = 1}) async {
    if (currentReceipt == null) return false;

    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return false;

    lastScannedCode = cleanCode;

    // Buscar en caché local
    ItemModel? item = itemsByCode[cleanCode.toUpperCase()];
    if (item == null) {
      final stripped = cleanCode.replaceFirst(RegExp(r'^0+'), '');
      item = itemsByCode[stripped.toUpperCase()];
    }

    // Buscar en ERPNext
    if (item == null) {
      try {
        final resolvedCode = await erpNextService.lookupBarcode(cleanCode);
        if (resolvedCode != null) {
          item = itemsByCode[resolvedCode];
          if (item == null) {
            item = await erpNextService.fetchItemByCode(resolvedCode);
            if (item != null) {
              itemsByCode[item.itemCode.toUpperCase()] = item;
            }
          }
        }
      } catch (e) {
        print('[MR] Error lookup: $e');
      }
    }

    // Si no existe, crear en ERPNext
    if (item == null) {
      try {
        final result = await erpNextService.createItem(
          itemCode: cleanCode,
          itemName: 'Item $cleanCode',
        );
        item = ItemModel.fromJson(result);
        itemsByCode[item.itemCode.toUpperCase()] = item;
        lastScanMessage = '🆕 Creado: ${item.itemName} (nuevo en ERPNext)';
        lastScanWasError = false;
      } catch (e) {
        lastScanMessage = '❌ Error creando "$cleanCode" en ERPNext';
        lastScanWasError = true;
        notifyListeners();
        return false;
      }
    }

    // Agregar o actualizar en la recepción
    final existingIndex = currentReceipt!.items.indexWhere(
      (i) => i.itemCode.toUpperCase() == item!.itemCode.toUpperCase(),
    );

    if (existingIndex >= 0) {
      currentReceipt!.items[existingIndex].qty += quantity;
      lastScanMessage = '✅ ${item.itemName} — qty: ${currentReceipt!.items[existingIndex].qty}';
    } else {
      currentReceipt!.items.add(MaterialReceiptItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        qty: quantity,
        warehouse: currentReceipt!.warehouse,
      ));
      lastScanMessage = '✅ Nuevo: ${item.itemName} — ${quantity}uds';
    }

    lastScanWasError = false;
    notifyListeners();
    return true;
  }

  /// Actualiza la cantidad de un item.
  void updateItemQty(int index, int newQty) {
    if (currentReceipt == null) return;
    if (index < 0 || index >= currentReceipt!.items.length) return;

    if (newQty <= 0) {
      currentReceipt!.items.removeAt(index);
    } else {
      currentReceipt!.items[index].qty = newQty;
    }
    notifyListeners();
  }

  /// Elimina un item de la recepción.
  void removeItem(int index) {
    if (currentReceipt == null) return;
    if (index >= 0 && index < currentReceipt!.items.length) {
      currentReceipt!.items.removeAt(index);
      notifyListeners();
    }
  }

  /// Guarda la recepción como borrador en ERPNext.
  Future<bool> saveReceipt() async {
    if (currentReceipt == null || currentReceipt!.items.isEmpty) {
      error = 'La recepción está vacía';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final items = currentReceipt!.items.map((item) => item.toMap()).toList();

      Map<String, dynamic> result;

      if (isSaved && currentReceipt!.id != null) {
        result = await erpNextService.updatePurchaseReceipt(
          name: currentReceipt!.id!,
          items: items,
        );
      } else {
        // Crear como Purchase Receipt
        if (currentReceipt!.purchaseOrder.isNotEmpty) {
          // Con PO vinculada
          result = await erpNextService.createPurchaseReceipt(
            purchaseOrder: currentReceipt!.purchaseOrder,
            supplier: currentReceipt!.supplierId.isNotEmpty
                ? currentReceipt!.supplierId
                : currentReceipt!.supplier,
            warehouse: currentReceipt!.warehouse,
            items: items,
            namingSeries: currentReceipt!.namingSeries,
            costCenter: currentReceipt!.costCenter,
          );
        } else {
          // Sin PO — creación directa
          result = await erpNextService.createDirectPurchaseReceipt(
            supplier: currentReceipt!.supplierId.isNotEmpty
                ? currentReceipt!.supplierId
                : currentReceipt!.supplier,
            warehouse: currentReceipt!.warehouse,
            items: items,
            namingSeries: currentReceipt!.namingSeries,
            costCenter: currentReceipt!.costCenter,
          );
        }
      }

      currentReceipt!.id = result['name'];
      currentReceipt!.status = 'Borrador';
      isSaved = true;

      // Refrescar la lista de recepciones para que aparezca la nueva
      fetchReceipts();

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Error guardando borrador: $e';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Hace submit de la recepción.
  Future<bool> submitReceipt() async {
    if (currentReceipt == null) {
      error = 'No hay recepción para enviar';
      notifyListeners();
      return false;
    }

    if (!isSaved || currentReceipt!.id == null) {
      error = 'Primero guardá la recepción como borrador';
      notifyListeners();
      return false;
    }

    if (currentReceipt!.items.isEmpty) {
      error = 'La recepción no tiene items';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      await erpNextService.submitPurchaseReceipt(currentReceipt!.id!);
      currentReceipt!.status = 'Enviada';
      isSubmitted = true;

      // Refrescar la lista de recepciones para que actualice el estado
      fetchReceipts();

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Error enviando recepción: $e';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Refresca la recepción desde ERPNext.
  Future<void> refreshReceipt() async {
    if (currentReceipt?.id == null) return;
    await loadReceipt(currentReceipt!.id!);
  }

  /// Limpia la recepción actual.
  void clearCurrentReceipt() {
    currentReceipt = null;
    isSaved = false;
    isSubmitted = false;
    lastScannedCode = '';
    lastScanMessage = '';
    notifyListeners();
  }
}
