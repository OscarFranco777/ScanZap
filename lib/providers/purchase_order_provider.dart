import 'package:flutter/material.dart';
import '../models/purchase_order.dart';
import '../models/item_model.dart';
import '../services/erpnext_service.dart';

/// Estado del módulo de Órdenes de Compra.
class PurchaseOrderProvider with ChangeNotifier {
  final ErpNextService erpNextService;

  // ─── Estado ───
  bool isLoading = false;
  String error = '';

  // ─── Estado del guardado ───
  bool isSaved = false; // true cuando el borrador ya está en ERPNext
  bool isSubmitted = false; // true cuando fue enviado (submit)

  // ─── Orden actual (en edición) ───
  PurchaseOrder? currentOrder;

  // ─── Lista de órdenes ───
  List<Map<String, dynamic>> ordersList = [];

  // ─── Items cacheados del inventario ───
  Map<String, ItemModel> itemsByCode = {};

  // ─── Catálogos para dropdowns ───
  List<Map<String, dynamic>> warehouses = [];
  List<Map<String, dynamic>> costCenters = [];
  bool catalogsLoaded = false;

  // ─── Último escaneo ───
  String lastScannedCode = '';
  String lastScanMessage = '';
  bool lastScanWasError = false;

  PurchaseOrderProvider({required this.erpNextService});

  /// Carga la caché de items desde el provider principal.
  void loadItemsCache(Map<String, ItemModel> cache) {
    itemsByCode = cache;
  }

  // ══════════════════════════════════════════════════════════════
  // ÓRDENES
  // ══════════════════════════════════════════════════════════════

  /// Lista órdenes de compra desde ERPNext.
  Future<void> fetchOrders() async {
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      ordersList = await erpNextService.listPurchaseOrders();
    } catch (e) {
      error = 'Error cargando órdenes: $e';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Carga catálogos de almacenes y centros de costo desde ERPNext.
  Future<void> fetchCatalogs() async {
    try {
      final results = await Future.wait([
        erpNextService.fetchWarehouses(),
        erpNextService.fetchCostCenters(),
      ]);
      warehouses = results[0];
      costCenters = results[1];
    } catch (e) {
      print('[PO] Error cargando catálogos: $e');
    } finally {
      catalogsLoaded = true;
      notifyListeners();
    }
  }

  /// Crea una nueva orden local (borrador).
  void createNewOrder({
    required String supplier,
    String supplierId = '',
    required DateTime date,
    String costCenter = '',
    String setWarehouse = '',
  }) {
    currentOrder = PurchaseOrder(
      supplier: supplier,
      supplierId: supplierId,
      scheduleDate: date,
      costCenter: costCenter,
      setWarehouse: setWarehouse,
    );
    notifyListeners();
  }

  /// Carga una orden existente desde ERPNext.
  Future<void> loadOrder(String name) async {
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final data = await erpNextService.getPurchaseOrder(name);
      if (data != null) {
        currentOrder = PurchaseOrder.fromErp(data);
        // Si ya tiene ID, está guardada; si docstatus=1, está enviada
        isSaved = currentOrder!.id != null;
        isSubmitted = currentOrder!.status == 'Enviada';
      } else {
        error = 'Orden no encontrada';
      }
    } catch (e) {
      error = 'Error cargando orden: $e';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Agrega un item escaneado a la orden actual.
  /// Si el item no existe en ERPNext, lo crea automáticamente.
  Future<bool> scanItemToOrder(String code, {int quantity = 1}) async {
    if (currentOrder == null) return false;

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
      print('[PO] Buscando "$cleanCode" en ERPNext...');
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
        print('[PO] Error lookup: $e');
      }
    }

    // Si no existe, crear en ERPNext
    if (item == null) {
      print('[PO] Item no existe, creando en ERPNext...');
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
        print('[PO] Error creando item: $e');
        lastScanMessage = '❌ Error creando "$cleanCode" en ERPNext';
        lastScanWasError = true;
        notifyListeners();
        return false;
      }
    }

    // Agregar o actualizar en la orden
    final existingIndex = currentOrder!.items.indexWhere(
      (i) => i.itemCode.toUpperCase() == item!.itemCode.toUpperCase(),
    );

    if (existingIndex >= 0) {
      currentOrder!.items[existingIndex].qty += quantity;
      lastScanMessage = '✅ ${item.itemName} — qty: ${currentOrder!.items[existingIndex].qty}';
    } else {
      currentOrder!.items.add(PurchaseOrderItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        qty: quantity,
      ));
      lastScanMessage = '✅ Nuevo: ${item.itemName} — ${quantity}uds';
    }

    lastScanWasError = false;
    notifyListeners();
    return true;
  }

  /// Actualiza la cantidad de un item.
  void updateItemQty(int index, int newQty) {
    if (currentOrder == null) return;
    if (index < 0 || index >= currentOrder!.items.length) return;

    if (newQty <= 0) {
      currentOrder!.items.removeAt(index);
    } else {
      currentOrder!.items[index].qty = newQty;
    }
    notifyListeners();
  }

  /// Elimina un item de la orden.
  void removeItem(int index) {
    if (currentOrder == null) return;
    if (index >= 0 && index < currentOrder!.items.length) {
      currentOrder!.items.removeAt(index);
      notifyListeners();
    }
  }

  /// Refresca la orden desde ERPNext.
  Future<void> refreshOrder() async {
    if (currentOrder?.id == null) return;
    await loadOrder(currentOrder!.id!);
  }

  /// Guarda la orden como borrador en ERPNext.
  Future<bool> saveOrder() async {
    if (currentOrder == null || currentOrder!.items.isEmpty) {
      error = 'La orden está vacía';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final supplier = currentOrder!.supplierId.isNotEmpty
          ? currentOrder!.supplierId
          : currentOrder!.supplier;
      final dateStr = currentOrder!.scheduleDate.toIso8601String().substring(0, 10);
      final items = currentOrder!.items.map((item) => item.toMap()).toList();

      Map<String, dynamic> result;

      if (isSaved && currentOrder!.id != null) {
        // Actualizar borrador existente
        result = await erpNextService.updatePurchaseOrder(
          name: currentOrder!.id!,
          items: items,
        );
      } else {
        // Crear nuevo borrador
        result = await erpNextService.savePurchaseOrder(
          supplier: supplier,
          scheduleDate: dateStr,
          items: items,
          costCenter: currentOrder!.costCenter,
          setWarehouse: currentOrder!.setWarehouse,
        );
      }

      currentOrder!.id = result['name'];
      currentOrder!.status = 'Borrador';
      currentOrder!.grandTotal = result['grand_total']?.toDouble() ?? 0;
      isSaved = true;

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

  /// Hace submit de la orden (de borrador a enviada). Requiere que esté guardada.
  Future<bool> submitOrder() async {
    if (currentOrder == null) {
      error = 'No hay orden para enviar';
      notifyListeners();
      return false;
    }

    if (!isSaved || currentOrder!.id == null) {
      error = 'Primero guardá la orden como borrador';
      notifyListeners();
      return false;
    }

    if (currentOrder!.items.isEmpty) {
      error = 'La orden no tiene items';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      await erpNextService.submitPurchaseOrder(currentOrder!.id!);

      currentOrder!.status = 'Enviada';
      isSubmitted = true;

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Error enviando orden: $e';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpia la orden actual.
  void clearCurrentOrder() {
    currentOrder = null;
    isSaved = false;
    isSubmitted = false;
    lastScannedCode = '';
    lastScanMessage = '';
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  // BÚSQUEDA DE PROVEEDORES
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    if (query.length < 2) return [];
    return await erpNextService.searchSuppliers(query);
  }
}
