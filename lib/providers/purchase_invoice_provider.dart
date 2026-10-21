import 'package:flutter/material.dart';
import '../models/purchase_invoice.dart';
import '../models/item_model.dart';
import '../services/erpnext_service.dart';

/// Estado del módulo de Facturas de Compra (Purchase Invoice).
/// El tilde "Actualizar inventario" (update_stock) se marca según el origen:
/// - Creación directa → true
/// - Desde una Purchase Order (sin recepción) → true
/// - Desde un Purchase Receipt → false (el stock ya lo actualizó la recepción)
class PurchaseInvoiceProvider with ChangeNotifier {
  final ErpNextService erpNextService;

  // ─── Estado ───
  bool isLoading = false;
  String error = '';

  // ─── Estado del guardado ───
  bool isSaved = false;
  bool isSubmitted = false;

  // ─── Loading para creación desde PO / PR ───
  bool _loadingInvoice = false;
  bool get loadingInvoice => _loadingInvoice;

  // ─── Factura actual (en edición) ───
  PurchaseInvoice? currentInvoice;

  // ─── Lista de facturas ───
  List<Map<String, dynamic>> invoicesList = [];

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

  PurchaseInvoiceProvider({required this.erpNextService});

  /// Carga la caché de items desde el provider principal.
  void loadItemsCache(Map<String, ItemModel> cache) {
    itemsByCode = cache;
  }

  // ══════════════════════════════════════════════════════════════
  // FACTURAS
  // ══════════════════════════════════════════════════════════════

  /// Lista facturas de compra desde ERPNext.
  Future<void> fetchInvoices() async {
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      invoicesList = await erpNextService.listPurchaseInvoices();
    } catch (e) {
      error = 'Error cargando facturas: $e';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Carga catálogos (almacenes, naming series PI, centros de costo) desde ERPNext.
  /// Si la app aún no conectó (URL vacía), espera hasta 30s a que conecte.
  Future<void> fetchCatalogs() async {
    for (var i = 0; i < 30 && erpNextService.baseUrl.isEmpty; i++) {
      await Future.delayed(const Duration(seconds: 1));
    }
    try {
      final results = await Future.wait([
        erpNextService.fetchWarehouses(),
        erpNextService.fetchNamingSeries('Purchase Invoice'),
        erpNextService.fetchCostCenters(),
        // Config de UOMs (cuáles admiten decimales) — para libras, kg, etc.
        erpNextService.ensureUomSettingsLoaded(),
      ]);
      warehouses = List<Map<String, dynamic>>.from(results[0] as List);
      namingSeriesOptions = List<String>.from(results[1] as List);
      costCenters = List<Map<String, dynamic>>.from(results[2] as List);
    } catch (e) {
      print('[PI] Error cargando catálogos: $e');
    } finally {
      catalogsLoaded = true;
      notifyListeners();
    }
  }

  /// Busca proveedores por nombre.
  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    return await erpNextService.searchSuppliers(query);
  }

  /// Crea una factura local (borrador, creación directa → update_stock true).
  void createNewInvoice({
    String supplier = '',
    String supplierId = '',
    String billNo = '',
    String namingSeries = '',
    String warehouse = '',
    String costCenter = '',
    bool updateStock = true,
    DateTime? postingDate,
  }) {
    currentInvoice = PurchaseInvoice(
      supplier: supplier,
      supplierId: supplierId,
      billNo: billNo,
      namingSeries: namingSeries,
      warehouse: warehouse,
      costCenter: costCenter,
      updateStock: updateStock,
      postingDate: postingDate ?? DateTime.now(),
    );
    isSaved = false;
    isSubmitted = false;
    notifyListeners();
  }

  /// Crea una factura desde los items pendientes de una Purchase Order enviada.
  /// Sin recepción previa → update_stock = true.
  Future<void> createFromPO(
    String poName, {
    String supplier = '',
    String supplierId = '',
    String billNo = '',
    String namingSeries = '',
    String warehouse = '',
    String costCenter = '',
  }) async {
    _loadingInvoice = true;
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final poItems = await erpNextService.getPurchaseOrderItems(poName);

      final invItems = <PurchaseInvoiceItem>[];
      for (final item in poItems) {
        // Cantidad pendiente de facturar (qty - billed_qty si viene)
        final qty = (item['qty'] ?? 0).toDouble();
        final billedQty = (item['billed_qty'] != null)
            ? (item['billed_qty'] as num).toDouble()
            : 0.0;
        final pending = qty - billedQty;
        if (pending <= 0) continue; // item ya facturado
        invItems.add(PurchaseInvoiceItem(
          itemCode: item['item_code'] ?? '',
          itemName: item['item_name'] ?? '',
          qty: pending,
          uom: item['uom'] ?? '',
          warehouse: warehouse.isNotEmpty ? warehouse : (item['warehouse'] ?? ''),
          rate: (item['rate'] ?? 0).toDouble(),
          purchaseOrderItem: item['name'] ?? '',
        ));
      }

      // Si no se pasó warehouse, tomar del primer item
      final effectiveWarehouse = warehouse.isNotEmpty
          ? warehouse
          : (invItems.isNotEmpty ? invItems.first.warehouse : '');

      currentInvoice = PurchaseInvoice(
        supplier: supplier,
        supplierId: supplierId.isNotEmpty ? supplierId : supplier,
        billNo: billNo,
        purchaseOrder: poName,
        namingSeries: namingSeries,
        warehouse: effectiveWarehouse,
        costCenter: costCenter,
        updateStock: true, // Orden → factura directa: actualizar inventario
        items: invItems,
      );
      isSaved = false;
      isSubmitted = false;
    } catch (e) {
      error = 'Error cargando items de PO: $e';
    }

    _loadingInvoice = false;
    isLoading = false;
    notifyListeners();
  }

  /// Crea una factura desde los items pendientes de un Purchase Receipt enviado.
  /// El stock ya lo actualizó la recepción → update_stock = false.
  Future<void> createFromReceipt(
    String receiptName, {
    String supplier = '',
    String supplierId = '',
    String billNo = '',
    String namingSeries = '',
    String warehouse = '',
    String costCenter = '',
  }) async {
    _loadingInvoice = true;
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final prItems = await erpNextService.getPurchaseReceiptItems(receiptName);

      final invItems = <PurchaseInvoiceItem>[];
      for (final item in prItems) {
        // Cantidad pendiente de facturar (qty - billed_qty si viene)
        final qty = (item['qty'] ?? 0).toDouble();
        final billedQty = (item['billed_qty'] != null)
            ? (item['billed_qty'] as num).toDouble()
            : 0.0;
        final pending = qty - billedQty;
        if (pending <= 0) continue; // item ya facturado
        invItems.add(PurchaseInvoiceItem(
          itemCode: item['item_code'] ?? '',
          itemName: item['item_name'] ?? '',
          qty: pending,
          uom: item['uom'] ?? '',
          warehouse: warehouse.isNotEmpty ? warehouse : (item['warehouse'] ?? ''),
          rate: (item['rate'] ?? 0).toDouble(),
          purchaseReceiptItem: item['name'] ?? '',
        ));
      }

      // Si no se pasó warehouse, tomar del primer item
      final effectiveWarehouse = warehouse.isNotEmpty
          ? warehouse
          : (invItems.isNotEmpty ? invItems.first.warehouse : '');

      final effectiveSupplier = supplierId.isNotEmpty
          ? supplierId
          : (supplier.isNotEmpty
              ? supplier
              : (prItems.isNotEmpty ? (prItems.first['supplier'] ?? '') : ''));

      currentInvoice = PurchaseInvoice(
        supplier: effectiveSupplier,
        supplierId: effectiveSupplier,
        billNo: billNo,
        purchaseReceipt: receiptName,
        namingSeries: namingSeries,
        warehouse: effectiveWarehouse,
        costCenter: costCenter.isNotEmpty && prItems.isNotEmpty
            ? costCenter
            : (prItems.isNotEmpty ? (prItems.first['cost_center'] ?? '') : ''),
        updateStock: false, // Desde recepción: NO actualizar inventario
        items: invItems,
      );
      isSaved = false;
      isSubmitted = false;
    } catch (e) {
      error = 'Error cargando items de la recepción: $e';
    }

    _loadingInvoice = false;
    isLoading = false;
    notifyListeners();
  }

  /// Carga una factura existente desde ERPNext.
  Future<void> loadInvoice(String name) async {
    _loadingInvoice = true;
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final data = await erpNextService.getPurchaseInvoice(name);

      if (data != null) {
        currentInvoice = PurchaseInvoice.fromErp(data);
        isSaved = currentInvoice!.id != null;
        isSubmitted = currentInvoice!.status == 'Enviada';
      } else {
        error = 'Factura no encontrada';
      }
    } catch (e) {
      error = 'Error cargando factura: $e';
    }

    _loadingInvoice = false;
    isLoading = false;
    notifyListeners();
  }

  /// Resuelve la UOM del item (del item mismo o desde la caché).
  String _itemUom(PurchaseInvoiceItem item) {
    if (item.uom.isNotEmpty) return item.uom;
    final cached = itemsByCode[item.itemCode.toUpperCase()];
    return cached?.stockUom ?? '';
  }

  /// Agrega un item a la factura por código, SIN crear items nuevos
  /// (usado por la búsqueda manual: solo items existentes del ERP).
  Future<bool> addItemToInvoiceByCode(String code, {double quantity = 1}) async {
    if (currentInvoice == null) return false;

    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return false;

    // Buscar en caché local o traer del ERP
    ItemModel? item = itemsByCode[cleanCode.toUpperCase()];
    if (item == null) {
      final stripped = cleanCode.replaceFirst(RegExp(r'^0+'), '');
      item = itemsByCode[stripped.toUpperCase()];
    }
    if (item == null) {
      try {
        item = await erpNextService.fetchItemByCode(cleanCode);
        if (item != null) {
          itemsByCode[item.itemCode.toUpperCase()] = item;
        }
      } catch (e) {
        print('[PI] Error fetch item: $e');
      }
    }

    if (item == null) {
      lastScanMessage = '❌ Item "$cleanCode" no encontrado en ERPNext';
      lastScanWasError = true;
      notifyListeners();
      return false;
    }

    // LIFO: el producto recién agregado siempre queda de primero en la pila.
    final existingIndex = currentInvoice!.items.indexWhere(
      (i) => i.itemCode.toUpperCase() == item!.itemCode.toUpperCase(),
    );
    if (existingIndex >= 0) {
      final updated = currentInvoice!.items.removeAt(existingIndex);
      updated.qty += quantity;
      currentInvoice!.items.insert(0, updated);
      lastScanMessage = '✅ ${item.itemName} — qty: ${updated.qty}';
    } else {
      currentInvoice!.items.insert(0, PurchaseInvoiceItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        qty: quantity,
        warehouse: currentInvoice!.warehouse,
      ));
      lastScanMessage = '✅ Nuevo: ${item.itemName} — ${quantity}uds';
    }

    lastScanWasError = false;
    notifyListeners();
    return true;
  }

  /// Agrega un item escaneado a la factura actual (con resolución de barcode;
  /// sin crear items nuevos — en facturación no se inventan productos).
  Future<bool> scanItemToInvoice(String code, {double quantity = 1}) async {
    if (currentInvoice == null) return false;

    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return false;

    lastScannedCode = cleanCode;

    // Buscar en caché local
    ItemModel? item = itemsByCode[cleanCode.toUpperCase()];
    if (item == null) {
      final stripped = cleanCode.replaceFirst(RegExp(r'^0+'), '');
      item = itemsByCode[stripped.toUpperCase()];
    }

    // Buscar en ERPNext (barcode o item_code)
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
        print('[PI] Error lookup: $e');
      }
    }

    if (item == null) {
      try {
        item = await erpNextService.fetchItemByCode(cleanCode);
        if (item != null) {
          itemsByCode[item.itemCode.toUpperCase()] = item;
        }
      } catch (e) {
        print('[PI] Error fetch item: $e');
      }
    }

    if (item == null) {
      lastScanMessage = '❌ Item "$cleanCode" no encontrado en ERPNext';
      lastScanWasError = true;
      notifyListeners();
      return false;
    }

    // Agregar o actualizar en la factura — LIFO: lo recién escaneado de primero
    final existingIndex = currentInvoice!.items.indexWhere(
      (i) => i.itemCode.toUpperCase() == item!.itemCode.toUpperCase(),
    );
    if (existingIndex >= 0) {
      final updated = currentInvoice!.items.removeAt(existingIndex);
      updated.qty += quantity;
      currentInvoice!.items.insert(0, updated);
      lastScanMessage = '✅ ${item.itemName} — qty: ${updated.qty}';
    } else {
      currentInvoice!.items.insert(0, PurchaseInvoiceItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        qty: quantity,
        uom: item.stockUom,
        warehouse: currentInvoice!.warehouse,
      ));
      lastScanMessage = '✅ Nuevo: ${item.itemName} — ${quantity}uds';
    }

    lastScanWasError = false;
    notifyListeners();
    return true;
  }

  /// Actualiza la cantidad de un item.
  void updateItemQty(int index, double newQty) {
    if (currentInvoice == null) return;
    if (index < 0 || index >= currentInvoice!.items.length) return;

    if (newQty <= 0) {
      currentInvoice!.items.removeAt(index);
    } else {
      currentInvoice!.items[index].qty = newQty;
    }
    notifyListeners();
  }

  /// Actualiza el rate de un item (sin notify para no perder cursor del TextField).
  void updateItemRate(int index, double value) {
    if (currentInvoice == null) return;
    if (index < 0 || index >= currentInvoice!.items.length) return;
    currentInvoice!.items[index].rate = value;
  }

  /// Actualiza el Nº de factura del proveedor.
  void updateBillNo(String value) {
    if (currentInvoice == null) return;
    currentInvoice!.billNo = value;
  }

  /// Actualiza el tilde "Actualizar inventario".
  void setUpdateStock(bool value) {
    if (currentInvoice == null) return;
    currentInvoice!.updateStock = value;
    notifyListeners();
  }

  /// Elimina un item de la factura.
  void removeItem(int index) {
    if (currentInvoice == null) return;
    if (index >= 0 && index < currentInvoice!.items.length) {
      currentInvoice!.items.removeAt(index);
      notifyListeners();
    }
  }

  /// Serializa los items actuales para el servicio.
  List<Map<String, dynamic>> _itemsPayload() {
    return currentInvoice!.items
        .map((item) => item.toMap(
              purchaseOrder: currentInvoice!.purchaseOrder,
              purchaseReceipt: currentInvoice!.purchaseReceipt,
            ))
        .toList();
  }

  /// Guarda la factura como borrador en ERPNext.
  Future<bool> saveInvoice() async {
    if (currentInvoice == null || currentInvoice!.items.isEmpty) {
      error = 'La factura está vacía';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final items = _itemsPayload();
      final supplier = currentInvoice!.supplierId.isNotEmpty
          ? currentInvoice!.supplierId
          : currentInvoice!.supplier;

      Map<String, dynamic> result;

      if (isSaved && currentInvoice!.id != null) {
        result = await erpNextService.updatePurchaseInvoice(
          name: currentInvoice!.id!,
          items: items,
          billNo: currentInvoice!.billNo,
          updateStock: currentInvoice!.updateStock,
        );
      } else if (currentInvoice!.purchaseReceipt.isNotEmpty) {
        // Con recepción vinculada
        result = await erpNextService.createPurchaseInvoiceFromReceipt(
          purchaseReceipt: currentInvoice!.purchaseReceipt,
          supplier: supplier,
          items: items,
          billNo: currentInvoice!.billNo,
          namingSeries: currentInvoice!.namingSeries,
          costCenter: currentInvoice!.costCenter,
          setWarehouse: currentInvoice!.warehouse,
          updateStock: currentInvoice!.updateStock,
        );
      } else if (currentInvoice!.purchaseOrder.isNotEmpty) {
        // Con orden vinculada (sin recepción)
        result = await erpNextService.createPurchaseInvoiceFromPO(
          purchaseOrder: currentInvoice!.purchaseOrder,
          supplier: supplier,
          items: items,
          billNo: currentInvoice!.billNo,
          namingSeries: currentInvoice!.namingSeries,
          costCenter: currentInvoice!.costCenter,
          setWarehouse: currentInvoice!.warehouse,
          updateStock: currentInvoice!.updateStock,
        );
      } else {
        // Creación directa
        result = await erpNextService.createDirectPurchaseInvoice(
          supplier: supplier,
          items: items,
          billNo: currentInvoice!.billNo,
          namingSeries: currentInvoice!.namingSeries,
          setWarehouse: currentInvoice!.warehouse,
          costCenter: currentInvoice!.costCenter,
          updateStock: currentInvoice!.updateStock,
        );
      }

      currentInvoice!.id = (result['name'] ?? currentInvoice!.id).toString();
      isSaved = true;

      // Refrescar desde el ERP: trae los costos reales que calculó el
      // sistema (precios, impuestos y totales) sin salir de la pantalla.
      await loadInvoice(currentInvoice!.id!);
      // El guardado sí funcionó; un fallo del refresco no invalida el guardado
      // (loadInvoice conserva el estado local si falla).
      error = '';

      // Refrescar la lista de facturas para que aparezca la nueva
      fetchInvoices();

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

  /// Hace submit de la factura.
  Future<bool> submitInvoice() async {
    if (currentInvoice == null) {
      error = 'No hay factura para enviar';
      notifyListeners();
      return false;
    }

    if (!isSaved || currentInvoice!.id == null) {
      error = 'Primero guardá la factura como borrador';
      notifyListeners();
      return false;
    }

    if (currentInvoice!.items.isEmpty) {
      error = 'La factura no tiene items';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      await erpNextService.submitPurchaseInvoice(currentInvoice!.id!);
      currentInvoice!.status = 'Enviada';
      isSubmitted = true;

      // Refrescar la lista de facturas para que actualice el estado
      fetchInvoices();

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Error enviando factura: $e';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpia la factura actual.
  void clearCurrentInvoice() {
    currentInvoice = null;
    isSaved = false;
    isSubmitted = false;
    lastScannedCode = '';
    lastScanMessage = '';
    // Resetear catálogos para forzar recarga en la pantalla de creación
    catalogsLoaded = false;
    namingSeriesOptions = [];
    warehouses = [];
    costCenters = [];
    notifyListeners();
  }
}
