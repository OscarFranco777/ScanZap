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
  List<String> namingSeriesOptions = [];
  String selectedNamingSeries = '';
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
        erpNextService.fetchNamingSeries('Purchase Order'),
      ]);
      warehouses = List<Map<String, dynamic>>.from(results[0] as List);
      costCenters = List<Map<String, dynamic>>.from(results[1] as List);
      namingSeriesOptions = List<String>.from(results[2] as List);
      if (namingSeriesOptions.isNotEmpty && selectedNamingSeries.isEmpty) {
        selectedNamingSeries = namingSeriesOptions.first;
      }
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
    String namingSeries = '',
  }) {
    currentOrder = PurchaseOrder(
      supplier: supplier,
      supplierId: supplierId,
      scheduleDate: date,
      costCenter: costCenter,
      setWarehouse: setWarehouse,
      namingSeries: namingSeries,
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
        isSubmitted = (data['docstatus'] ?? 0) == 1;
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
          namingSeries: currentOrder!.namingSeries,
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

      // El estado lo asigna el ERP tras el submit (normalmente "To Receive and Bill").
      // Lo leemos del servidor en vez de asumirlo.
      try {
        final statusData = await erpNextService.refreshPurchaseOrderStatus(
          currentOrder!.id!,
        );
        currentOrder!.erpStatus = (statusData['status'] ?? '').toString();
        currentOrder!.perBilled = (statusData['per_billed'] ?? 0).toDouble();
        currentOrder!.perReceived = (statusData['per_received'] ?? 0).toDouble();
      } catch (_) {
        currentOrder!.erpStatus = 'To Receive and Bill';
      }
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

  /// Cancela la orden enviada (docstatus 1 → 2). El ERP exige que no tenga
  /// recibos/facturas enviadas contra ella para permitir la cancelación.
  Future<bool> cancelOrder() async {
    if (currentOrder == null || currentOrder!.id == null) {
      error = 'No hay orden guardada para cancelar';
      notifyListeners();
      return false;
    }

    if (!isSubmitted) {
      error = 'Solo se puede cancelar una orden enviada';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      await erpNextService.cancelPurchaseOrder(currentOrder!.id!);
      currentOrder!.status = 'Cancelada';
      currentOrder!.erpStatus = 'Cancelled';
      isSubmitted = false;

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Error cancelando orden: $e';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Crea y envía un Purchase Invoice contra la orden actual.
  /// Requiere orden enviada y no facturada al 100%.
  /// Al submitir la factura, el ERP actualiza per_billed y el status solo.
  Future<bool> createInvoiceForOrder({List<int>? itemIndexes}) async {
    final order = currentOrder;
    if (order == null || order.id == null) {
      error = 'No hay orden guardada para facturar';
      notifyListeners();
      return false;
    }

    if (!isSubmitted) {
      error = 'La orden debe estar enviada antes de facturar';
      notifyListeners();
      return false;
    }

    if (order.perBilled >= 100) {
      error = 'La orden ya está facturada al 100%';
      notifyListeners();
      return false;
    }

    isLoading = true;
    error = '';
    notifyListeners();

    try {
      // Traer los items reales del ERP (tienen po_detail y warehouse)
      final poItems = await erpNextService.getPurchaseOrderItems(order.id!);
      if (poItems.isEmpty) {
        error = 'La orden no tiene items en el ERP';
        isLoading = false;
        notifyListeners();
        return false;
      }

      // Filtrar por índice si el usuario factura parcial
      final selected = (itemIndexes == null || itemIndexes.isEmpty)
          ? poItems
          : [
              for (final i in itemIndexes)
                if (i >= 0 && i < poItems.length) poItems[i],
            ];

      final invItems = selected.map((it) {
        // Cantidad pendiente de facturar (qty - billed_qty si viene)
        final qty = (it['qty'] ?? 0).toDouble();
        final billedQty = (it['billed_qty'] != null)
            ? (it['billed_qty'] as num).toDouble()
            : 0.0;
        final pending = qty - billedQty;
        return {
          'item_code': it['item_code'],
          'qty': pending > 0 ? pending : qty,
          'rate': it['rate'] ?? 0,
          'warehouse': it['warehouse'] ?? order.setWarehouse,
          'purchase_order_item': it['name'], // po_detail
          'uom': it['uom'],
        };
      }).toList();

      final invoice = await erpNextService.createPurchaseInvoiceFromPO(
        purchaseOrder: order.id!,
        supplier: order.supplierId.isNotEmpty ? order.supplierId : order.supplier,
        items: invItems,
        costCenter: order.costCenter,
        setWarehouse: order.setWarehouse,
      );

      final invoiceName = invoice['name']?.toString() ?? '';
      if (invoiceName.isEmpty) {
        throw Exception('El ERP no devolvió el nombre de la factura');
      }

      // Submit de la factura: el ERP recalcula per_billed y status de la orden
      await erpNextService.submitPurchaseInvoice(invoiceName);

      // Refrescar el estado real de la orden desde el servidor
      final statusData = await erpNextService.refreshPurchaseOrderStatus(order.id!);
      order.erpStatus = (statusData['status'] ?? '').toString();
      order.perBilled = (statusData['per_billed'] ?? 0).toDouble();
      order.perReceived = (statusData['per_received'] ?? 0).toDouble();

      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Error facturando orden: $e';
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
