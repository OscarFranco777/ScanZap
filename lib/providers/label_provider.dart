import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item_model.dart';
import '../models/label_settings.dart';
import '../models/label_template.dart';
import '../services/erpnext_service.dart';
import '../services/label_printer_service.dart';
import 'inventory_provider.dart';

/// Una etiqueta impresa (para el historial de la sesión).
class PrintedLabel {
  final String itemCode;
  final String itemName;
  final double price;
  final int copies;
  final DateTime at;

  PrintedLabel({
    required this.itemCode,
    required this.itemName,
    required this.price,
    required this.copies,
    required this.at,
  });
}

/// Estado del módulo de Etiquetas de Precio.
///
/// Flujo: escanear → resolver item por cualquiera de sus códigos de barras
/// (multi-barcode, vía InventoryProvider) → traer precio de la lista
/// configurada → imprimir por Bluetooth.
class LabelProvider with ChangeNotifier {
  final ErpNextService erpNextService;
  final LabelPrinterService printerService = LabelPrinterService();

  LabelProvider({required this.erpNextService});

  // ─── Configuración ───
  LabelSettings settings = LabelSettings();
  bool settingsLoaded = false;

  // ─── Plantilla de etiqueta (diseñador) ───
  LabelTemplate? template;

  /// Plantilla activa: la guardada, o la por defecto (modelo del cliente).
  LabelTemplate get effectiveTemplate =>
      template ??
      LabelTemplate.defaultTemplate(
        widthMm: settings.widthMm,
        heightMm: settings.heightMm,
      );

  // ─── Listas de precios disponibles ───
  List<String> priceLists = [];
  bool loadingPriceLists = false;

  // ─── Impresoras Bluetooth emparejadas ───
  List<BtDevice> btDevices = [];
  bool btEnabled = false;
  bool btLoading = false;

  /// Refresca el estado de Bluetooth y la lista de impresoras emparejadas.
  /// Pide el permiso runtime BLUETOOTH_CONNECT (Android 12+) ANTES de
  /// tocar el plugin — sin él el plugin revienta a nivel nativo.
  /// [promptEnable]: solo en llamada explícita del usuario (botón
  /// refrescar); nunca al abrir una pantalla (el diálogo del sistema
  /// de encender BT no debe aparecer solo).
  Future<void> refreshBluetooth({bool promptEnable = false}) async {
    if (btLoading) return;
    btLoading = true;
    notifyListeners();

    if (!printerService.isSupported) {
      btEnabled = false;
      btLoading = false;
      notifyListeners();
      return;
    }

    btEnabled = await printerService.ensureBluetoothReady(
      promptEnable: promptEnable,
    );
    if (btEnabled) {
      btDevices = await printerService.listBondedDevices();
    }
    btLoading = false;
    notifyListeners();
  }

  /// Busca un dispositivo emparejado por MAC (para mostrar el nombre
  /// guardado aunque el escaneo actual no lo incluya).
  BtDevice? deviceByMac(String mac) {
    for (final d in btDevices) {
      if (d.address == mac) return d;
    }
    return null;
  }

  // ─── Estado de impresión ───
  bool isPrinting = false;
  String lastPrintMessage = '';
  bool lastPrintWasError = false;

  // ─── Búsqueda actual ───
  ItemModel? currentItem;
  double? currentItemPrice;
  bool searchingItem = false;
  String searchMessage = '';

  // ─── Historial de la sesión ───
  final List<PrintedLabel> history = [];

  /// Símbolo de la moneda de la company: el código ISO (HNL, GTQ, USD...)
  /// se traduce al símbolo que la gente reconoce en el precio (L, Q, $...).
  String get currencySymbol {
    switch (erpNextService.currency.toUpperCase()) {
      case 'HNL':
        return 'L'; // Lempira hondureño
      case 'GTQ':
        return 'Q'; // Quetzal
      case 'USD':
        return r'$';
      case 'CRC':
        return '₡';
      case 'EUR':
        return '€';
      default:
        return erpNextService.currency;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CONFIGURACIÓN
  // ══════════════════════════════════════════════════════════════

  Future<void> loadSettings() async {
    settings = await LabelSettings.load();
    settingsLoaded = true;
    notifyListeners();
  }

  Future<void> updateSettings(LabelSettings newSettings) async {
    settings = newSettings;
    await settings.save();
    notifyListeners();
  }

  /// Carga la plantilla guardada (si hay).
  Future<void> loadTemplate() async {
    template = await LabelTemplate.load();
    notifyListeners();
  }

  /// Guarda la plantilla desde el diseñador y (opcionalmente) activa su uso.
  /// Si hay sesión activa, también la sube al ERP para que todos los
  /// dispositivos usen el mismo diseño.
  Future<void> saveTemplate(LabelTemplate t,
      {bool enable = true, bool pushToErp = true}) async {
    template = t;
    await t.save();
    if (settings.useTemplate != enable) {
      settings = LabelSettings.from(settings)..useTemplate = enable;
      await settings.save();
    }
    if (pushToErp && erpNextService.loggedUser.isNotEmpty) {
      try {
        await erpNextService.uploadLabelTemplate(jsonEncode(t.toJson()));
        templateSyncMessage = 'Plantilla guardada y subida al ERP';
      } catch (e) {
        templateSyncMessage =
            'Guardada local, pero falló subirla al ERP: $e';
      }
    } else {
      templateSyncMessage = null;
    }
    notifyListeners();
  }

  // ─── Sincronización de la plantilla con el ERP ───
  bool syncingTemplate = false;
  String? templateSyncMessage;

  /// Sincroniza la plantilla con el ERP (diseño único para todos los
  /// dispositivos). Si en el ERP aún no hay plantilla y acá sí, la sube;
  /// si hay una remota distinta, la baja y reemplaza la local.
  /// Solo hace algo con sesión activa; sin internet falla silencioso.
  Future<bool> syncTemplateFromErp() async {
    if (syncingTemplate) return false;
    if (erpNextService.loggedUser.isEmpty) return false;

    syncingTemplate = true;
    notifyListeners();
    try {
      final jsonStr = await erpNextService.fetchLabelTemplate();
      if (jsonStr == null) {
        // El ERP no tiene plantilla: si hay una local, la subimos.
        if (template != null) {
          await erpNextService
              .uploadLabelTemplate(jsonEncode(template!.toJson()));
          templateSyncMessage = 'Plantilla local subida al ERP';
        }
        return true;
      }
      final remote =
          LabelTemplate.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      // Comparar normalizados (re-serializados) para evitar falsos cambios.
      final remoteJson = jsonEncode(remote.toJson());
      final localJson =
          template == null ? null : jsonEncode(template!.toJson());
      if (localJson != remoteJson) {
        template = remote;
        await remote.save();
        templateSyncMessage = 'Plantilla actualizada desde el ERP';
      } else {
        templateSyncMessage = null;
      }
      return true;
    } catch (e) {
      templateSyncMessage = 'Error sincronizando plantilla: $e';
      return false;
    } finally {
      syncingTemplate = false;
      notifyListeners();
    }
  }

  /// Activa/desactiva el uso de la plantilla.
  Future<void> setUseTemplate(bool enable) async {
    settings = LabelSettings.from(settings)..useTemplate = enable;
    await settings.save();
    notifyListeners();
  }

  /// Restaura la plantilla por defecto (modelo del cliente).
  Future<void> resetTemplate() async {
    template = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(LabelTemplate.kJsonKey);
    notifyListeners();
  }

  /// Carga las listas de precios de venta disponibles en ERPNext.
  Future<void> loadPriceLists() async {
    if (loadingPriceLists) return;
    loadingPriceLists = true;
    notifyListeners();
    try {
      priceLists = await erpNextService.fetchPriceLists();
    } catch (_) {
      priceLists = [];
    }
    loadingPriceLists = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  // BÚSQUEDA DE ITEM POR CÓDIGO (multi-barcode)
  // ══════════════════════════════════════════════════════════════

  /// Resuelve un código escaneado/escrito → item + precio de la lista.
  /// Reutiliza el índice de barcodes del InventoryProvider (offline,
  /// ya cargado al conectar) con fallback a lookup online.
  Future<void> resolveCode(
    String code,
    InventoryProvider inventory,
  ) async {
    final clean = code.trim();
    if (clean.isEmpty) return;

    searchingItem = true;
    currentItem = null;
    currentItemPrice = null;
    searchMessage = '';
    notifyListeners();

    try {
      // 1) Resolver el código a item (multi-barcode, offline primero)
      ItemModel? item = inventory.resolveBarcodeLocal(clean);

      // 2) Fallback: lookup online en ERPNext
      if (item == null) {
        final onlineCode = await erpNextService.lookupBarcode(clean);
        if (onlineCode != null) {
          item = inventory.itemsByCode[onlineCode.toUpperCase()] ??
              inventory.itemsByCode[onlineCode];
          item ??= await erpNextService.fetchItemByCode(onlineCode);
        }
      }

      // 3) Último recurso: match directo por item_code
      item ??= inventory.itemsByCode[clean.toUpperCase()];

      if (item == null) {
        searchMessage = 'Producto no encontrado para "$clean"';
        searchingItem = false;
        notifyListeners();
        return;
      }

      currentItem = item;

      // 4) Precio en la lista configurada
      if (settings.priceList.isEmpty) {
        searchMessage =
            'Configurá la lista de precios por defecto para ver el precio.';
      } else {
        currentItemPrice = await erpNextService.fetchItemPrice(
          itemCode: item.itemCode,
          priceList: settings.priceList,
        );
        if (currentItemPrice == null) {
          searchMessage =
              'El producto "${item.itemName}" no tiene precio en la lista "${settings.priceList}".';
        }
      }
    } catch (e) {
      searchMessage = 'Error buscando el producto: $e';
    }

    searchingItem = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  // IMPRESIÓN
  // ══════════════════════════════════════════════════════════════

  /// Formatea el precio con el símbolo de la moneda de la company.
  /// Sin locale del dispositivo: formateo manual (1,234.50) para que
  /// funcione igual offline y en cualquier teléfono.
  String formatPrice(double price) {
    final neg = price < 0;
    final abs = price.abs();
    final whole = abs.floor();
    final cents = ((abs - whole) * 100).round();
    final digits = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buf.write(digits[i]);
      final rest = digits.length - i - 1;
      if (rest > 0 && rest % 3 == 0) buf.write(',');
    }
    return '$currencySymbol ${neg ? '-' : ''}${buf.toString()}.${cents.toString().padLeft(2, '0')}';
  }

  /// Arma los datos de etiqueta del item actual e imprime.
  Future<void> printCurrentItem({int? copies}) async {
    final item = currentItem;
    final price = currentItemPrice;
    if (item == null) {
      lastPrintWasError = true;
      lastPrintMessage = 'Primero escaneá o buscá un producto.';
      notifyListeners();
      return;
    }

    isPrinting = true;
    lastPrintMessage = '';
    notifyListeners();

    try {
      // Elegir el mejor código de barras del item para codificar.
      final barcode = bestBarcodeFor(
        _pickBarcode(item),
      );

      final label = LabelData(
        itemName: item.itemName,
        itemCode: item.itemCode,
        barcode: barcode,
        priceText: price != null ? formatPrice(price) : '',
        uom: item.stockUom,
      );

      await printerService.printLabel(
        label: label,
        settings: settings,
        copies: copies,
      );

      history.insert(
        0,
        PrintedLabel(
          itemCode: item.itemCode,
          itemName: item.itemName,
          price: price ?? 0,
          copies: copies ?? settings.copies,
          at: DateTime.now(),
        ),
      );
      if (history.length > 50) history.removeLast();

      lastPrintWasError = false;
      lastPrintMessage =
          '✅ ${copies ?? settings.copies} etiqueta(s) enviada(s) a "${settings.printerName}".';
    } catch (e) {
      lastPrintWasError = true;
      lastPrintMessage = e.toString().replaceFirst('Exception: ', '');
    }

    isPrinting = false;
    notifyListeners();
  }

  /// Elige el código de barras a codificar: el campo barcode del item si
  /// existe, si no el item_code (patrón de la instancia: coinciden).
  String _pickBarcode(ItemModel item) {
    if (item.barcode.trim().isNotEmpty) return item.barcode.trim();
    return item.itemCode;
  }

  /// Conecta a la impresora configurada (para probar conexión desde la UI).
  Future<bool> testConnection() async {
    if (settings.printerMac.isEmpty) return false;
    return await printerService.connect(settings.printerMac);
  }
}
