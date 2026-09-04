import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/item_model.dart';
import '../models/inventory_row.dart';
import '../services/erpnext_service.dart';
import '../services/excel_service.dart';

/// Estado global de la aplicación de inventario.
/// Gestiona la conexión, datos, conteo y exportación.
class InventoryProvider with ChangeNotifier {
  // ─── Servicios ───
  final ErpNextService erpNextService;
  final ExcelService excelService = ExcelService();

  // ─── Estado de conexión ───
  bool isConnected = false;
  bool isLoadingItems = false;
  String connectionError = '';

  // ─── Datos base ───
  List<ItemModel> allItems = [];
  Map<String, ItemModel> itemsByCode = {};
  Map<String, String> barcodesToItemCode = {};

  // ─── Estado de Excel ───
  bool excelLoaded = false;
  String excelFileName = '';
  int excelMatchCount = 0;

  // ─── Sesión de inventario ───
  final Map<String, InventoryRow> _sessionItems = {};
  String lastScannedCode = '';
  String lastScanMessage = '';
  bool lastScanWasError = false;

  // ─── Config ERPNext ───
  String warehouse = '';

  // ─── Getters ───
  List<InventoryRow> get scannedItems =>
      _sessionItems.values.toList()
        ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));

  int get totalUnitsScanned =>
      _sessionItems.values.fold(0, (sum, row) => sum + row.quantity);

  double get totalInventoryValue =>
      _sessionItems.values.fold(0.0, (sum, row) => sum + row.totalCost);

  int get uniqueProducts => _sessionItems.length;

  bool get isReady => isConnected && excelLoaded;

  String get loggedUser => erpNextService.loggedUser;

  InventoryProvider({required this.erpNextService});

  // ══════════════════════════════════════════════════════════════
  // CONEXIÓN A ERPNext (por sesión)
  // ══════════════════════════════════════════════════════════════

  /// Conecta a ERPNext con usuario/contraseña y carga productos.
  Future<bool> connectToErpNext({
    required String url,
    required String username,
    required String password,
    bool rememberMe = false,
    void Function(int loaded, int? total)? onProgress,
  }) async {
    connectionError = '';
    isLoadingItems = true;
    notifyListeners();

    try {
      erpNextService.configure(url: url);

      // Login por sesión
      try {
        final user = await erpNextService.login(
          username: username,
          password: password,
        );
        if (user.isEmpty) {
          connectionError = 'No se pudo autenticar con ERPNext.';
          isConnected = false;
          isLoadingItems = false;
          notifyListeners();
          return false;
        }
      } catch (e) {
        connectionError = e.toString().replaceFirst('Exception: ', '');
        isConnected = false;
        isLoadingItems = false;
        notifyListeners();
        return false;
      }

      // Cargar items con barcodes
      final result = await erpNextService.fetchAllItemsAndBarcodes(onProgress: onProgress);
      allItems = result.items;
      barcodesToItemCode = result.barcodeMap;

      itemsByCode.clear();
      for (final item in allItems) {
        itemsByCode[item.itemCode.toUpperCase()] = item;
        if (item.name.toUpperCase() != item.itemCode.toUpperCase()) {
          itemsByCode[item.name.toUpperCase()] = item;
        }
      }

      print('[Provider] Items indexados: ${itemsByCode.length} entradas');
      print('[Provider] Barcodes secundarios: ${barcodesToItemCode.length} entradas');

      isConnected = true;
      isLoadingItems = false;

      // Guardar configuración
      await _saveConfig(url, username, rememberMe ? password : '');
      notifyListeners();
      return true;
    } catch (e) {
      connectionError = 'Error de conexión: $e';
      isConnected = false;
      isLoadingItems = false;
      notifyListeners();
      return false;
    }
  }

  /// Cierra la sesión actual.
  Future<void> disconnect() async {
    await erpNextService.logout();
    isConnected = false;
    allItems.clear();
    itemsByCode.clear();
    barcodesToItemCode.clear();
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  // CARGA DE EXCEL
  // ══════════════════════════════════════════════════════════════

  void processExcel({
    required Uint8List fileBytes,
    required String fileName,
    int codigoColumn = 0,
    int costoColumn = 2,
  }) {
    excelService.parseExcel(
      fileBytes,
      codigoColumn: codigoColumn,
      costoColumn: costoColumn,
    );

    excelFileName = fileName;
    excelLoaded = excelService.costoMap.isNotEmpty;

    if (isConnected) {
      excelMatchCount = 0;
      for (final code in excelService.costoMap.keys) {
        if (itemsByCode.containsKey(code)) {
          excelMatchCount++;
        } else {
          final stripped = code.replaceFirst(RegExp(r'^0+'), '');
          if (stripped != code && itemsByCode.containsKey(stripped)) {
            excelMatchCount++;
          }
        }
      }
    }

    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  // ESCANEO Y CONTEO
  // ══════════════════════════════════════════════════════════════

  Future<bool> scanItem(String code, {int quantity = 1}) async {
    final cleanCode = code.trim();
    if (cleanCode.isEmpty) return false;

    lastScannedCode = cleanCode;
    print('[Scan] Buscando código: "$cleanCode"');

    final strippedCode = cleanCode.replaceFirst(RegExp(r'^0+'), '');
    final upperCode = cleanCode.toUpperCase();
    final upperStripped = strippedCode.toUpperCase();

    var item = itemsByCode[upperCode];
    if (item == null && upperStripped != upperCode) {
      item = itemsByCode[upperStripped];
    }

    if (item == null) {
      var resolvedCode = barcodesToItemCode[upperCode];
      if (resolvedCode == null && upperStripped != upperCode) {
        resolvedCode = barcodesToItemCode[upperStripped];
      }
      if (resolvedCode != null) {
        item = itemsByCode[resolvedCode];
        if (item == null) {
          final strippedResolved = resolvedCode.replaceFirst(RegExp(r'^0+'), '');
          item = itemsByCode[strippedResolved];
        }
      }
    }

    if (item == null && erpNextService.baseUrl.isNotEmpty) {
      print('[Scan] No encontrado localmente, buscando en ERPNext...');
      try {
        final resolvedCode = await erpNextService.lookupBarcode(cleanCode);
        if (resolvedCode != null) {
          item = itemsByCode[resolvedCode];
          if (item == null) {
            item = await erpNextService.fetchItemByCode(resolvedCode);
            if (item != null) {
              itemsByCode[item.itemCode.toUpperCase()] = item;
              if (item.name.toUpperCase() != item.itemCode.toUpperCase()) {
                itemsByCode[item.name.toUpperCase()] = item;
              }
            }
          }
        }
      } catch (e) {
        print('[Scan] Error en lookup ERPNext: $e');
      }
    }

    if (item == null) {
      print('[Scan] ❌ NO ENCONTRADO');
      lastScanMessage = '❌ Producto "$cleanCode" no encontrado en ERPNext';
      lastScanWasError = true;
      notifyListeners();
      return false;
    }

    final cost = excelService.getCost(item.itemCode);

    if (_sessionItems.containsKey(item.itemCode.toUpperCase())) {
      _sessionItems[item.itemCode.toUpperCase()]!.addQuantity(quantity);
      lastScanMessage =
          '✅ ${item.itemName} — cantidad: ${_sessionItems[item.itemCode.toUpperCase()]!.quantity}';
    } else {
      _sessionItems[item.itemCode.toUpperCase()] = InventoryRow(
        itemCode: item.itemCode,
        displayCode: item.barcode.isNotEmpty && item.barcode != item.itemCode
            ? item.barcode
            : cleanCode.toUpperCase(),
        itemName: item.itemName,
        stockUom: item.stockUom,
        quantity: quantity,
        unitCost: cost ?? 0.0,
        hasCost: cost != null && cost > 0,
      );
      lastScanMessage = cost != null
          ? '✅ Nuevo: ${item.itemName} — ${quantity}uds — L${(cost * quantity).toStringAsFixed(2)}'
          : '⚠️ Nuevo: ${item.itemName} — ¡Sin costo!';
    }

    lastScanWasError = false;
    notifyListeners();
    return true;
  }

  void updateQuantity(String itemCode, int newQty) {
    final key = itemCode.toUpperCase();
    if (_sessionItems.containsKey(key)) {
      _sessionItems[key]!.setQuantity(newQty);
      if (newQty == 0) {
        _sessionItems.remove(key);
      }
      notifyListeners();
    }
  }

  void incrementQuantity(String itemCode) {
    final key = itemCode.toUpperCase();
    if (_sessionItems.containsKey(key)) {
      _sessionItems[key]!.increment();
      notifyListeners();
    }
  }

  void decrementQuantity(String itemCode) {
    final key = itemCode.toUpperCase();
    if (_sessionItems.containsKey(key)) {
      _sessionItems[key]!.decrement();
      if (_sessionItems[key]!.quantity == 0) {
        _sessionItems.remove(key);
      }
      notifyListeners();
    }
  }

  void removeItem(String itemCode) {
    _sessionItems.remove(itemCode.toUpperCase());
    notifyListeners();
  }

  void clearSession() {
    _sessionItems.clear();
    lastScannedCode = '';
    lastScanMessage = '';
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  // EXPORTACIÓN
  // ══════════════════════════════════════════════════════════════

  Uint8List? generateExcelReport() {
    if (_sessionItems.isEmpty) return null;

    final excel = Excel.createExcel();
    final sheet = excel['Inventario'];

    final headers = [
      'Barcode Escaneado',
      'Código ERP',
      'Nombre',
      'UOM',
      'Cantidad',
      'Costo Unitario',
      'Costo Total',
      'Estado',
    ];

    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        ..value = TextCellValue(headers[i])
        ..cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#2196F3'),
          fontColorHex: ExcelColor.white,
        );
    }

    int row = 1;
    for (final item in scannedItems) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = TextCellValue(item.displayCode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = TextCellValue(item.itemCode);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
          .value = TextCellValue(item.itemName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
          .value = TextCellValue(item.stockUom);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
          .value = IntCellValue(item.quantity);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
          .value = DoubleCellValue(item.unitCost);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
          .value = DoubleCellValue(item.totalCost);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
          .value = TextCellValue(item.hasCost ? 'OK' : 'Sin Costo');
      row++;
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
        .value = TextCellValue('TOTAL');
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
        .value = IntCellValue(totalUnitsScanned);
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
        .value = DoubleCellValue(totalInventoryValue);

    return Uint8List.fromList(excel.save() ?? []);
  }

  List<Map<String, dynamic>> toStockReconciliationItems() {
    return scannedItems
        .where((r) => r.hasCost)
        .map((r) => {
              'item_code': r.itemCode,
              'quantity': r.quantity,
              'unit_cost': r.unitCost,
            })
        .toList();
  }

  Future<Map<String, dynamic>> sendToErpNext({
    required String warehouseCode,
  }) async {
    warehouse = warehouseCode;
    final items = toStockReconciliationItems();
    if (items.isEmpty) {
      throw Exception('No hay items con costo para enviar.');
    }
    return erpNextService.createStockReconciliation(
      warehouse: warehouseCode,
      items: items,
    );
  }

  Future<void> refreshItems() async {
    if (!isConnected) return;
    isLoadingItems = true;
    notifyListeners();

    try {
      final result = await erpNextService.fetchAllItemsAndBarcodes();
      allItems = result.items;
      barcodesToItemCode = result.barcodeMap;

      itemsByCode.clear();
      for (final item in allItems) {
        itemsByCode[item.itemCode.toUpperCase()] = item;
        if (item.name.toUpperCase() != item.itemCode.toUpperCase()) {
          itemsByCode[item.name.toUpperCase()] = item;
        }
      }

      isConnected = true;
    } catch (e) {
      connectionError = 'Error al refrescar: $e';
    }

    isLoadingItems = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  // PERSISTENCIA
  // ══════════════════════════════════════════════════════════════

  Future<void> _saveConfig(String url, String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('erpnext_url', url);
    await prefs.setString('erpnext_username', username);
    // Solo guardar contraseña si "Recordarme" está activo
    if (password.isNotEmpty) {
      await prefs.setString('erpnext_password', password);
      await prefs.setBool('erpnext_remember', true);
    } else {
      await prefs.remove('erpnext_password');
      await prefs.setBool('erpnext_remember', false);
    }
  }

  Future<Map<String, String>> loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'url': prefs.getString('erpnext_url') ?? '',
      'username': prefs.getString('erpnext_username') ?? '',
      'password': prefs.getString('erpnext_password') ?? '',
      'remember': (prefs.getBool('erpnext_remember') ?? false).toString(),
    };
  }
}
