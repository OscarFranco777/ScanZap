import 'package:flutter/material.dart';
import '../models/stock_entry.dart';
import '../models/item_model.dart';
import '../services/erpnext_service.dart';

/// Estado del módulo de Entradas de Inventario (Stock Entry).
/// Tipos soportados (traídos del ERP): Material Receipt,
/// Material Transfer y Material Issue.
class StockEntryProvider with ChangeNotifier {
  final ErpNextService erpNextService;

  // ─── Estado ───
  bool isLoading = false;
  String error = '';

  // ─── Estado del guardado ───
  bool isSaved = false;
  bool isSubmitted = false;

  // ─── Entrada actual (en edición) ───
  StockEntry? currentEntry;

  // ─── Lista de entradas ───
  List<Map<String, dynamic>> entriesList = [];

  // ─── Items cacheados del inventario ───
  Map<String, ItemModel> itemsByCode = {};

  // ─── Almacenes ───
  List<Map<String, dynamic>> warehouses = [];

  // ─── Centros de costo ───
  List<Map<String, dynamic>> costCenters = [];

  // ─── Tipos de entrada (del ERP) ───
  List<String> stockEntryTypes = [];

  // ─── Naming series ───
  List<String> namingSeriesOptions = [];
  bool catalogsLoaded = false;

  // ─── Último escaneo ───
  String lastScannedCode = '';
  String lastScanMessage = '';
  bool lastScanWasError = false;

  StockEntryProvider({required this.erpNextService});

  /// Carga la caché de items desde el provider principal.
  void loadItemsCache(Map<String, ItemModel> cache) {
    itemsByCode = cache;
  }

  // ══════════════════════════════════════════════════════════════
  // ENTRADAS
  // ══════════════════════════════════════════════════════════════

  /// Lista entradas de inventario desde ERPNext.
  Future<void> fetchEntries() async {
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      entriesList = await erpNextService.listStockEntries();
    } catch (e) {
      error = 'Error cargando entradas: $e';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Carga catálogos (tipos de entrada, almacenes, series, centros de costo)
  /// desde ERPNext. Si la app aún no conectó (URL vacía), espera hasta 30s.
  Future<void> fetchCatalogs() async {
    for (var i = 0; i < 30 && erpNextService.baseUrl.isEmpty; i++) {
      await Future.delayed(const Duration(seconds: 1));
    }
    try {
      final results = await Future.wait([
        erpNextService.fetchStockEntryTypes(),
        erpNextService.fetchWarehouses(),
        erpNextService.fetchCostCenters(),
        erpNextService.fetchStockEntryNamingSeries(),
        // Config de UOMs (cuáles admiten decimales) — para libras, kg, etc.
        erpNextService.ensureUomSettingsLoaded(),
      ]);
      final types = List<Map<String, dynamic>>.from(results[0] as List);
      // Tipos primero (orden del ERP), luego series
      stockEntryTypes = types.map((t) => (t['name'] ?? '').toString()).toList();
      warehouses = List<Map<String, dynamic>>.from(results[1] as List);
      costCenters = List<Map<String, dynamic>>.from(results[2] as List);
      namingSeriesOptions = List<String>.from(results[3] as List);
    } catch (e) {
      print('[SE] Error cargando catálogos: $e');
    } finally {
      catalogsLoaded = true;
      notifyListeners();
    }
  }

  /// Crea una entrada local (borrador).
  void createNewEntry({
    String stockEntryType = '',
    String sourceWarehouse = '',
    String targetWarehouse = '',
    String costCenter = '',
    String remarks = '',
    String namingSeries = '',
    DateTime? postingDate,
  }) {
    currentEntry = StockEntry(
      stockEntryType: stockEntryType,
      sourceWarehouse: sourceWarehouse,
      targetWarehouse: targetWarehouse,
      costCenter: costCenter,
      remarks: remarks,
      namingSeries: namingSeries,
      postingDate: postingDate ?? DateTime.now(),
    );
    isSaved = false;
    isSubmitted = false;
    notifyListeners();
  }

  /// Carga una entrada existente desde ERPNext.
  Future<void> loadEntry(String name) async {
    _loadingEntry = true;
    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final data = await erpNextService.getStockEntry(name);

      if (data != null) {
        currentEntry = StockEntry.fromErp(data);
        isSaved = currentEntry!.id != null;
        isSubmitted = currentEntry!.status == 'Enviada';
      } else {
        error = 'Entrada no encontrada';
      }
    } catch (e) {
      error = 'Error cargando entrada: $e';
    }

    _loadingEntry = false;
    isLoading = false;
    notifyListeners();
  }

  bool _loadingEntry = false;
  bool get loadingEntry => _loadingEntry;

  /// Agrega un item a la entrada por código, SIN crear items nuevos
  /// (usado por la búsqueda manual: solo items existentes del ERP).
  Future<bool> addItemToEntryByCode(String code, {double quantity = 1}) async {
    if (currentEntry == null) return false;

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
        print('[SE] Error fetch item: $e');
      }
    }

    if (item == null) {
      lastScanMessage = '❌ Item "$cleanCode" no encontrado en ERPNext';
      lastScanWasError = true;
      notifyListeners();
      return false;
    }

    // LIFO: el producto recién agregado siempre queda de primero en la pila.
    final existingIndex = currentEntry!.items.indexWhere(
      (i) => i.itemCode.toUpperCase() == item!.itemCode.toUpperCase(),
    );
    if (existingIndex >= 0) {
      final updated = currentEntry!.items.removeAt(existingIndex);
      updated.qty += quantity;
      currentEntry!.items.insert(0, updated);
      lastScanMessage = '✅ ${item.itemName} — qty: ${updated.qty}';
    } else {
      currentEntry!.items.insert(0, StockEntryItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        qty: quantity,
        uom: item.stockUom,
        sourceWarehouse: currentEntry!.sourceWarehouse,
        targetWarehouse: currentEntry!.targetWarehouse,
      ));
      lastScanMessage = '✅ Nuevo: ${item.itemName} — ${quantity}uds';
    }

    lastScanWasError = false;
    notifyListeners();
    return true;
  }

  /// Agrega un item escaneado a la entrada actual (con resolución de barcode;
  /// si no existe lo CREA en ERPNext — misma lógica que la Recepción).
  Future<bool> scanItemToEntry(String code, {double quantity = 1}) async {
    if (currentEntry == null) return false;

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
        print('[SE] Error lookup: $e');
      }
    }

    if (item == null) {
      try {
        item = await erpNextService.fetchItemByCode(cleanCode);
        if (item != null) {
          itemsByCode[item.itemCode.toUpperCase()] = item;
        }
      } catch (e) {
        print('[SE] Error fetch item: $e');
      }
    }

    // Si no existe, crear en ERPNext (misma lógica que la Recepción)
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
        print('[SE] Error creando item: $e');
        lastScanMessage = '❌ Error creando "$cleanCode" en ERPNext';
        lastScanWasError = true;
        notifyListeners();
        return false;
      }
    }

    // Agregar o actualizar en la entrada — LIFO: lo recién escaneado de primero
    final existingIndex = currentEntry!.items.indexWhere(
      (i) => i.itemCode.toUpperCase() == item!.itemCode.toUpperCase(),
    );
    if (existingIndex >= 0) {
      final updated = currentEntry!.items.removeAt(existingIndex);
      updated.qty += quantity;
      currentEntry!.items.insert(0, updated);
      lastScanMessage = '✅ ${item.itemName} — qty: ${updated.qty}';
    } else {
      currentEntry!.items.insert(0, StockEntryItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        qty: quantity,
        uom: item.stockUom,
        sourceWarehouse: currentEntry!.sourceWarehouse,
        targetWarehouse: currentEntry!.targetWarehouse,
      ));
      lastScanMessage = '✅ Nuevo: ${item.itemName} — ${quantity}uds';
    }

    lastScanWasError = false;
    notifyListeners();
    return true;
  }

  /// Actualiza el precio base de un item (solo Material Receipt).
  void updateItemRate(int index, double value) {
    if (currentEntry == null) return;
    if (index < 0 || index >= currentEntry!.items.length) return;
    currentEntry!.items[index].basicRate = value;
    notifyListeners();
  }

  /// Actualiza la cantidad de un item.
  void updateItemQty(int index, double newQty) {
    if (currentEntry == null) return;
    if (index < 0 || index >= currentEntry!.items.length) return;

    if (newQty <= 0) {
      currentEntry!.items.removeAt(index);
    } else {
      currentEntry!.items[index].qty = newQty;
    }
    notifyListeners();
  }

  /// Actualiza las observaciones.
  void updateRemarks(String value) {
    if (currentEntry == null) return;
    currentEntry!.remarks = value;
  }

  /// Elimina un item de la entrada.
  void removeItem(int index) {
    if (currentEntry == null) return;
    if (index >= 0 && index < currentEntry!.items.length) {
      currentEntry!.items.removeAt(index);
      notifyListeners();
    }
  }

  /// Guarda la entrada como borrador en ERPNext.
  Future<bool> saveEntry() async {
    if (currentEntry == null || currentEntry!.items.isEmpty) {
      error = 'La entrada está vacía';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      final items = currentEntry!.items
          .map((item) => item.toMap(costCenter: currentEntry!.costCenter))
          .toList();

      Map<String, dynamic> result;

      if (isSaved && currentEntry!.id != null) {
        result = await erpNextService.updateStockEntry(
          name: currentEntry!.id!,
          stockEntryType: currentEntry!.stockEntryType,
          items: items,
          sourceWarehouse: currentEntry!.sourceWarehouse,
          targetWarehouse: currentEntry!.targetWarehouse,
          costCenter: currentEntry!.costCenter,
          remarks: currentEntry!.remarks,
        );
      } else {
        result = await erpNextService.createStockEntry(
          stockEntryType: currentEntry!.stockEntryType,
          items: items,
          sourceWarehouse: currentEntry!.sourceWarehouse,
          targetWarehouse: currentEntry!.targetWarehouse,
          costCenter: currentEntry!.costCenter,
          remarks: currentEntry!.remarks,
          namingSeries: currentEntry!.namingSeries,
        );
      }

      currentEntry!.id = result['name'];
      currentEntry!.status = 'Borrador';
      isSaved = true;

      // Refrescar la lista para que aparezca la nueva
      fetchEntries();

      // Refrescar la entrada desde ERPNext (trae costos reales si el ERP
      // los calculó) sin salir de la pantalla.
      await refreshEntry();

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

  /// Hace submit de la entrada.
  Future<bool> submitEntry() async {
    if (currentEntry == null) {
      error = 'No hay entrada para enviar';
      notifyListeners();
      return false;
    }

    if (!isSaved || currentEntry!.id == null) {
      error = 'Primero guardá la entrada como borrador';
      notifyListeners();
      return false;
    }

    if (currentEntry!.items.isEmpty) {
      error = 'La entrada no tiene items';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      await erpNextService.submitStockEntry(currentEntry!.id!);
      currentEntry!.status = 'Enviada';
      isSubmitted = true;

      // Refrescar la lista para que actualice el estado
      fetchEntries();

      // Refrescar la entrada desde ERPNext
      await refreshEntry();

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Error enviando entrada: $e';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Refresca la entrada desde ERPNext.
  Future<void> refreshEntry() async {
    if (currentEntry?.id == null) return;
    await loadEntry(currentEntry!.id!);
  }

  /// Limpia la entrada actual.
  void clearCurrentEntry() {
    currentEntry = null;
    isSaved = false;
    isSubmitted = false;
    lastScannedCode = '';
    lastScanMessage = '';
    // Resetear catálogos para forzar recarga en la pantalla de creación
    catalogsLoaded = false;
    stockEntryTypes = [];
    namingSeriesOptions = [];
    warehouses = [];
    costCenters = [];
    notifyListeners();
  }
}
