import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../models/item_model.dart';

/// UOM válida para el ERP: solo se manda si es real; si falta, el ERP
/// rellena la del item (stock_uom) solo y evita LinkValidationError.
bool _validUom(dynamic uom) =>
    uom is String && uom.trim().isNotEmpty && uom.trim() != 'Unidad';

/// Servicio para conectarse a la API REST de ERPNext/Frappe.
/// Versión Mobile — usa autenticación por sesión (usuario/contraseña).
class ErpNextService {
  String baseUrl = '';
  String _username = '';
  String _password = '';
  String currency = 'HNL'; // Moneda de la company (se actualiza al conectar)
  String? _company; // Nombre de la company (cacheado al conectar)
  String?
  _defaultPurchaseTaxTemplate; // Plantilla de impuestos de compra default (cacheada)

  late final Dio _dio;
  late final CookieJar _cookieJar;
  String _loggedUser = '';

  String get loggedUser => _loggedUser;
  String get username => _username;

  ErpNextService() {
    _cookieJar = CookieJar();
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  /// Configura la URL base (sin credenciales de sesión).
  void configure({required String url}) {
    var cleanUrl = url.trim();
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    baseUrl = cleanUrl;
  }

  /// Login con usuario y contraseña vía sesión (cookies).
  /// Retorna el usuario logueado o lanza excepción.
  Future<String> login({
    required String username,
    required String password,
  }) async {
    _username = username.trim();
    _password = password.trim();

    try {
      // Limpiar cookies anteriores
      await _cookieJar.deleteAll();

      final response = await _dio.post(
        '$baseUrl/api/method/login',
        data: {'usr': _username, 'pwd': _password},
        options: Options(
          contentType: 'application/x-www-form-urlencoded',
          headers: {'Accept': 'application/json'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['message'] == 'Logged In') {
          // Obtener el usuario logueado
          _loggedUser = await _getLoggedUser();
          return _loggedUser;
        }
      }

      throw Exception('Credenciales inválidas');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw Exception('Usuario o contraseña incorrectos');
      }
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Timeout — revisá la URL y tu conexión');
      }
      throw Exception('Error de login: ${e.message ?? e.toString()}');
    }
  }

  /// Obtiene el usuario actualmente logueado.
  Future<String> _getLoggedUser() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.auth.get_logged_user',
      );
      if (response.statusCode == 200) {
        return response.data?['message'] ?? 'desconocido';
      }
    } catch (_) {}
    return _username;
  }

  /// Cierra la sesión actual.
  Future<void> logout() async {
    try {
      await _dio.post('$baseUrl/api/method/logout');
    } catch (_) {}
    await _cookieJar.deleteAll();
    _loggedUser = '';
    _username = '';
    _password = '';
  }

  /// Verifica que la conexión funcione (sesión activa).
  Future<String> testConnection() async {
    try {
      final user = await _getLoggedUser();
      if (user.isNotEmpty && user != 'desconocido') {
        _loggedUser = user;
        return user;
      }
      throw Exception('No hay sesión activa');
    } catch (e) {
      throw Exception('Error de conexión: $e');
    }
  }

  /// Valida que el usuario tenga los permisos MÍNIMOS (leer + elegir/select)
  /// sobre los doctypes clave para operar: centro de costo, almacén y
  /// plantillas de impuestos. Devuelve una lista con el resultado de cada chequeo.
  Future<List<Map<String, dynamic>>> checkUserPermissions() async {
    const checks = [
      {'doctype': 'Cost Center', 'label': 'Centro de costo'},
      {'doctype': 'Warehouse', 'label': 'Almacén'},
      {
        'doctype': 'Purchase Taxes and Charges Template',
        'label': 'Plantilla de impuestos sobre compra',
      },
      {
        'doctype': 'Item Tax Template',
        'label': 'Impuesto del producto (Item Tax Template)',
      },
    ];
    final results = <Map<String, dynamic>>[];
    for (final c in checks) {
      final read = await _canReadDoctype(c['doctype']!);
      final select = await _canSelectDoctype(c['doctype']!);
      results.add({
        'label': c['label'],
        'doctype': c['doctype'],
        'read': read,
        'select': select,
        'ok': read && select,
      });
    }
    return results;
  }

  /// Prueba si el usuario puede ELEGIR (select) un doctype: es el permiso
  /// que usan los campos link y los buscadores del ERP.
  Future<bool> _canSelectDoctype(String doctype) async {
    try {
      final response = await _dio.post(
        '$baseUrl/api/method/frappe.desk.search.search_link',
        data: {
          'doctype': doctype,
          'txt': '',
        },
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Prueba si el usuario puede LEER un doctype. Ojo: get_list solo exige
  /// permiso de elegir (con select puro devuelve 200 con solo el nombre),
  /// así que primero saco un nombre con get_list y después pido el documento
  /// completo con frappe.client.get, que sí exige read de verdad.
  Future<bool> _canReadDoctype(String doctype) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': doctype,
          'fields': '["name"]',
          'limit_page_length': 1,
        },
      );
      if (response.statusCode != 200) return false;
      final rows = response.data?['message'];
      if (rows is! List || rows.isEmpty) return false;
      final name = rows.first['name']?.toString() ?? '';
      if (name.isEmpty) return false;

      // get del documento completo: 403 si no tiene read
      final docResponse = await _dio.get(
        '$baseUrl/api/method/frappe.client.get',
        queryParameters: {'doctype': doctype, 'name': name},
      );
      return docResponse.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Obtiene TODOS los productos con stock, incluyendo barcodes secundarios.
  Future<({List<ItemModel> items, Map<String, String> barcodeMap})>
  fetchAllItemsAndBarcodes({
    void Function(int loaded, int? total)? onProgress,
  }) async {
    onProgress?.call(0, null);

    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Item',
          'fields':
              '["name","item_code","item_name","stock_uom","barcodes.barcode"]',
          'filters': '[["is_stock_item","=",1]]',
          'limit_page_length': 50000,
        },
      );

      if (response.statusCode != 200) {
        print('[Service] Error HTTP ${response.statusCode}: ${response.data}');
        return (items: <ItemModel>[], barcodeMap: <String, String>{});
      }

      final List<dynamic> allRows = response.data?['message'] ?? [];
      print('[Service] Total filas recibidas: ${allRows.length}');

      final seenItems = <String, ItemModel>{};
      final barcodeMap = <String, String>{};

      for (final row in allRows) {
        final itemCode = (row['item_code'] ?? row['name'] ?? '').toString();
        String barcode = '';
        if (row['barcode'] != null) {
          if (row['barcode'] is num) {
            barcode = (row['barcode'] as num).toInt().toString();
          } else {
            barcode = row['barcode'].toString().trim();
          }
        }

        if (!seenItems.containsKey(itemCode.toUpperCase())) {
          seenItems[itemCode.toUpperCase()] = ItemModel.fromJson(row);
        }

        if (barcode.isNotEmpty) {
          final barcodeUpper = barcode.toUpperCase();
          barcodeMap[barcodeUpper] = itemCode.toUpperCase();
          final stripped = barcodeUpper.replaceFirst(RegExp(r'^0+'), '');
          if (stripped != barcodeUpper && stripped.isNotEmpty) {
            barcodeMap[stripped] = itemCode.toUpperCase();
          }
        }
      }

      final items = seenItems.values.toList();
      print('[Service] Items únicos: ${items.length}');
      print('[Service] Barcodes indexados: ${barcodeMap.length}');

      onProgress?.call(items.length, items.length);
      return (items: items, barcodeMap: barcodeMap);
    } catch (e) {
      print('[Service] fetchAllItemsAndBarcodes error: $e');
      return (items: <ItemModel>[], barcodeMap: <String, String>{});
    }
  }

  /// Busca un código de barras usando global_search.
  Future<String?> lookupBarcode(String code) async {
    try {
      print('[Service] Lookup barcode: "$code"');
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.utils.global_search.search',
        queryParameters: {'text': code.trim()},
      );

      if (response.statusCode != 200) {
        print('[Service] Lookup status: ${response.statusCode}');
        return null;
      }

      final List<dynamic> results = response.data?['message'] ?? [];
      print('[Service] Lookup resultados: ${results.length}');

      if (results.isEmpty) return null;

      for (final result in results) {
        if (result['doctype'] == 'Item' && result['name'] != null) {
          final itemCode = result['name'].toString();
          print('[Service] Lookup resuelto a: "$itemCode"');
          return itemCode;
        }
      }

      return null;
    } catch (e) {
      print('[Service] Lookup excepción: $e');
      return null;
    }
  }

  /// Obtiene un Item individual por su código.
  Future<ItemModel?> fetchItemByCode(String itemCode) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Item/${Uri.encodeComponent(itemCode)}',
        queryParameters: {
          'fields': '["name","item_code","item_name","stock_uom"]',
        },
      );

      if (response.statusCode == 200 && response.data?['data'] != null) {
        return ItemModel.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Crea un Item nuevo en ERPNext.
  Future<Map<String, dynamic>> createItem({
    required String itemCode,
    required String itemName,
    String stockUom = 'Unidad',
    bool isStockItem = true,
  }) async {
    final doc = {
      'doctype': 'Item',
      'item_code': itemCode,
      'item_name': itemName,
      'stock_uom': stockUom,
      'is_stock_item': isStockItem ? 1 : 0,
      'item_group': 'All Item Groups',
    };

    final response = await _dio.post('$baseUrl/api/resource/Item', data: doc);

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error creando item');
  }

  /// Obtiene el siguiente número de serie.
  Future<String> getNextSeriesNumber() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_next_number',
        queryParameters: {
          'doctype': 'Stock Reconciliation',
          'prefix': 'STK-REC',
        },
      );
      return response.data['message'] ?? 'STK-REC-00001';
    } catch (e) {
      return 'STK-REC-00001';
    }
  }

  /// Crea un Stock Reconciliation en ERPNext.
  Future<Map<String, dynamic>> createStockReconciliation({
    required String warehouse,
    required List<Map<String, dynamic>> items,
    String? namingSeries,
  }) async {
    final doc = {
      'doctype': 'Stock Reconciliation',
      'naming_series': namingSeries ?? 'STK-REC-.#####',
      'purpose': 'Physical Stock',
      'set_warehouse': warehouse,
      'items': items
          .map(
            (item) => {
              'doctype': 'Stock Reconciliation Item',
              'item_code': item['item_code'],
              'warehouse': warehouse,
              'qty_after_transaction': item['quantity'],
              'valuation_rate': item['unit_cost'],
            },
          )
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Stock%20Reconciliation',
      data: doc,
    );

    return response.data['data'] ?? {};
  }

  // ══════════════════════════════════════════════════════════════
  // NAMING SERIES
  // ══════════════════════════════════════════════════════════════

  /// Parsea opciones de naming_series desde un string (\n separadas).
  List<String> _parseNamingOptions(dynamic raw) {
    if (raw == null) return [];
    final str = raw.toString().trim();
    if (str.isEmpty) return [];
    return str
        .split(RegExp(r'[\n,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Obtiene las series de numeracion disponibles para un DocType.
  /// Usa frappe.client.get_meta (requiere permisos sobre el doctype, NO sobre DocType).
  Future<List<String>> fetchNamingSeries(String doctype) async {
    final allSeries = <String>{};

    // -- M1: frappe.desk.form.load.getdoctype --
    // Este es el endpoint que usa el frontend de Frappe cuando abris un form nuevo.
    // Retorna los campos del doctype incluyendo las opciones de naming_series.
    try {
      print('[NS] M1: getdoctype for $doctype');
      final r = await _dio.get(
        '$baseUrl/api/method/frappe.desk.form.load.getdoctype',
        queryParameters: {'doctype': doctype},
      );
      print('[NS] M1 status: ${r.statusCode}');
      if (r.statusCode == 200) {
        final docs = r.data?['docs'];
        if (docs is List) {
          for (final doc in docs) {
            if (doc is Map &&
                doc['doctype'] == 'DocType' &&
                doc['name'] == doctype) {
              // Buscar campo naming_series
              final fields = doc['fields'];
              if (fields is List) {
                for (final f in fields) {
                  if (f is Map && f['fieldname'] == 'naming_series') {
                    final raw = f['options']?.toString() ?? '';
                    final opts = _parseNamingOptions(raw);
                    print('[NS] M1 naming_series options: $opts');
                    allSeries.addAll(opts);
                  }
                }
              }
              break;
            }
          }
        }
      } else {
        final body = r.data?.toString() ?? '';
        print(
          '[NS] M1 body: ${body.substring(0, body.length > 300 ? 300 : body.length)}',
        );
      }
    } catch (e) {
      print('[NS] M1 error: $e');
    }

    // -- M2: frappe.client.get_list sobre el doctype (drafts + submitted) --
    // Busca TODOS los docs para encontrar series en uso
    try {
      print('[NS] M2: get_list docs for $doctype');
      final r = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': doctype,
          'fields': '["naming_series"]',
          'filters': jsonEncode([
            [
              'docstatus',
              'in',
              [0, 1],
            ],
          ]),
          'limit_page_length': 500,
          'order_by': 'creation desc',
        },
      );
      print('[NS] M2 status: ${r.statusCode}');
      if (r.statusCode == 200) {
        final List<dynamic> data = r.data?['message'] ?? [];
        print('[NS] M2 docs: ${data.length}');
        for (final row in data) {
          final val = (row['naming_series'] ?? '').toString().trim();
          if (val.isNotEmpty) allSeries.add(val);
        }
      }
    } catch (e) {
      print('[NS] M2 error: $e');
    }

    // -- M3: frappe.client.get_list sobre Document Naming Rule --
    try {
      print('[NS] M3: naming rules for $doctype');
      final r = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Document Naming Rule',
          'fields': '["name","prefix","document_type"]',
          'filters': jsonEncode([
            ['document_type', '=', doctype],
          ]),
          'limit_page_length': 50,
        },
      );
      print('[NS] M3 status: ${r.statusCode}');
      if (r.statusCode == 200) {
        final List<dynamic> data = r.data?['message'] ?? [];
        print('[NS] M3 rules: ${data.length}');
        for (final d in data) {
          final prefix = (d['prefix'] ?? '').toString().trim();
          if (prefix.isNotEmpty) allSeries.add(prefix);
        }
      }
    } catch (e) {
      print('[NS] M3 error: $e');
    }

    final result = allSeries.toList();
    print('[NS] TOTAL: ${result.length} series -> $result');
    return result;
  }

  // ALMACENES
  // ══════════════════════════════════════════════════════════════

  /// Lista almacenes activos de ERPNext.
  Future<List<Map<String, dynamic>>> fetchWarehouses() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Warehouse',
          'fields': '["name","warehouse_name"]',
          'filters': '[["is_group","=",0]]',
          'order_by': 'warehouse_name asc',
          'limit_page_length': 500,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] fetchWarehouses error: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CENTROS DE COSTOS
  // ══════════════════════════════════════════════════════════════

  /// Lista centros de costo activos de ERPNext.
  Future<List<Map<String, dynamic>>> fetchCostCenters() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Cost Center',
          'fields': '["name","cost_center_name"]',
          'filters': '[["disabled","=",0]]',
          'order_by': 'cost_center_name asc',
          'limit_page_length': 500,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] fetchCostCenters error: $e');
      return [];
    }
  }

  /// Busca items en ERPNext por código o nombre (búsqueda escrita manual).
  /// Devuelve filas con name, item_code, item_name y stock_uom.
  Future<List<Map<String, dynamic>>> searchItems(
    String query, {
    int limit = 20,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Item',
          'fields': '["name","item_code","item_name","stock_uom"]',
          'or_filters':
              '[["item_code","like","%$q%"],["item_name","like","%$q%"]]',
          'limit_page_length': limit,
          'order_by': 'item_code asc',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] searchItems error: $e');
      return [];
    }
  }

  // ─── UOM: permite decimales? (ERPNext: UOM.must_be_whole_number) ───
  // Cache: uom -> true si es "must be whole number" (NO admite decimales).
  final Map<String, bool> _uomWholeNumber = {};
  Future<void>? _uomSettingsFuture;

  /// Carga la config de todas las UOMs una sola vez (llamado al cargar catálogos).
  Future<void> ensureUomSettingsLoaded() {
    _uomSettingsFuture ??= _loadUomSettings();
    return _uomSettingsFuture!;
  }

  Future<void> _loadUomSettings() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'UOM',
          'fields': '["name","must_be_whole_number"]',
          'limit_page_length': 0,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        for (final row in data) {
          final name = (row['name'] ?? '').toString().toUpperCase();
          if (name.isEmpty) continue;
          _uomWholeNumber[name] = (row['must_be_whole_number'] ?? 0) == 1;
        }
        print('[Service] UOM settings cargadas: ${_uomWholeNumber.length}');
      }
    } catch (e) {
      print('[Service] Error cargando UOM settings: $e');
    }
  }

  /// true si la UOM admite cantidades decimales (ej: Libra).
  /// Si la UOM no está en el cache, asume que SÍ admite decimales.
  bool uomAllowsDecimals(String? uom) {
    if (uom == null || uom.trim().isEmpty) return true;
    final whole = _uomWholeNumber[uom.trim().toUpperCase()];
    return whole != true;
  }

  // ══════════════════════════════════════════════════════════════
  // PROVEEDORES (para Órdenes de Compra)
  // ══════════════════════════════════════════════════════════════

  /// Busca proveedores en ERPNext por nombre.
  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Supplier',
          'fields': '["name","supplier_name"]',
          'filters': '[["supplier_name","like","%$query%"]]',
          'limit_page_length': 20,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] searchSuppliers error: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════
  // ÓRDENES DE COMPRA
  // ══════════════════════════════════════════════════════════════

  /// Guarda una Purchase Order como borrador (docstatus=0) en ERPNext.
  Future<Map<String, dynamic>> savePurchaseOrder({
    required String supplier,
    required String scheduleDate,
    required List<Map<String, dynamic>> items,
    String costCenter = '',
    String setWarehouse = '',
    String namingSeries = '',
    String? taxesAndCharges,
  }) async {
    // Resolvemos la plantilla de impuestos de compra default si no vino una.
    // Sin ella el ERP no expande la tabla taxes vía API (en el UI lo hace el
    // trigger del browser, por API no corre) y la orden queda sin impuestos.
    final taxes = taxesAndCharges ?? await _getDefaultPurchaseTaxTemplate();
    final doc = {
      'doctype': 'Purchase Order',
      'supplier': supplier,
      'transaction_date': scheduleDate,
      'schedule_date': scheduleDate,
      'currency': currency,
      if (namingSeries.isNotEmpty) 'naming_series': namingSeries,
      if (costCenter.isNotEmpty) 'cost_center': costCenter,
      if (setWarehouse.isNotEmpty) 'set_warehouse': setWarehouse,
      if (taxes != null && taxes.isNotEmpty) 'taxes_and_charges': taxes,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Order Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'rate': item['rate'] ?? 0,
              'schedule_date': scheduleDate,
            },
          )
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Order',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error guardando borrador');
  }

  /// Actualiza un borrador existente en ERPNext (agrega/modifica items).
  Future<Map<String, dynamic>> updatePurchaseOrder({
    required String name,
    required List<Map<String, dynamic>> items,
    String? taxesAndCharges,
  }) async {
    // Reenviamos la plantilla default (si la orden vieja quedó sin impuestos,
    // el servidor la expande al validar; si ya tiene la misma, no toca nada).
    final taxes = taxesAndCharges ?? await _getDefaultPurchaseTaxTemplate();
    final doc = {
      if (taxes != null && taxes.isNotEmpty) 'taxes_and_charges': taxes,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Order Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'rate': item['rate'] ?? 0,
            },
          )
          .toList(),
    };

    final response = await _dio.put(
      '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(name)}',
      data: doc,
    );

    if (response.statusCode == 200) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error actualizando borrador');
  }

  /// Hace submit de una Purchase Order borrador (docstatus 0 → 1).
  /// Tras el submit el ERP asigna el estado (normalmente "To Receive and Bill").
  Future<Map<String, dynamic>> submitPurchaseOrder(String name) async {
    try {
      // Paso 1: Obtener el documento completo
      final docResponse = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(name)}',
      );
      if (docResponse.statusCode != 200 || docResponse.data?['data'] == null) {
        throw Exception('No se pudo obtener la orden $name para enviar');
      }
      final Map<String, dynamic> doc = docResponse.data['data'];

      // Paso 2: Enviar el documento completo a frappe.client.submit
      final response = await _dio.post(
        '$baseUrl/api/method/frappe.client.submit',
        data: {'doctype': 'Purchase Order', 'docname': name, 'doc': doc},
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw _erpResponseError(response, 'Error enviando orden');
    } on DioException catch (e) {
      throw _erpError(e, 'Error enviando orden');
    }
  }

  /// Cancela una Purchase Order enviada (docstatus 1 → 2).
  /// El ERP exige el documento completo para cancelar (igual que en submit).
  Future<Map<String, dynamic>> cancelPurchaseOrder(String name) async {
    try {
      final docResponse = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(name)}',
      );
      if (docResponse.statusCode != 200 || docResponse.data?['data'] == null) {
        throw Exception('No se pudo obtener la orden $name para cancelar');
      }
      final Map<String, dynamic> doc = docResponse.data['data'];

      final response = await _dio.post(
        '$baseUrl/api/method/frappe.client.cancel',
        data: {'doctype': 'Purchase Order', 'docname': name, 'doc': doc},
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw _erpResponseError(response, 'Error cancelando orden');
    } on DioException catch (e) {
      throw _erpError(e, 'Error cancelando orden');
    }
  }

  /// Lee el estado real de la orden desde el ERP (status, per_billed, per_received).
  /// La app NUNCA calcula el estado: lo muestra tal cual lo devuelve el servidor.
  Future<Map<String, dynamic>> refreshPurchaseOrderStatus(String name) async {
    final response = await _dio.get(
      '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(name)}',
      queryParameters: {
        'fields':
            '["name","status","docstatus","per_billed","per_received","grand_total"]',
      },
    );
    if (response.statusCode == 200 && response.data?['data'] != null) {
      return Map<String, dynamic>.from(response.data['data']);
    }
    throw Exception('No se pudo leer el estado de la orden $name');
  }

  /// Crea un Purchase Invoice como borrador desde una Purchase Order enviada.
  /// Los items deben traer item_code, qty, rate, purchase_order_item (po_detail)
  /// y warehouse para que el ERP vincule la factura con la orden.
  /// [updateStock] en true hace que la factura misma actualice el inventario
  /// (flujo orden → factura sin recepción previa).
  Future<Map<String, dynamic>> createPurchaseInvoiceFromPO({
    required String purchaseOrder,
    required String supplier,
    required List<Map<String, dynamic>> items,
    String? taxesAndCharges,
    String? costCenter,
    String? setWarehouse,
    String? billNo,
    String? namingSeries,
    bool updateStock = true,
  }) async {
    final doc = {
      'doctype': 'Purchase Invoice',
      'supplier': supplier,
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      'bill_date': DateTime.now().toIso8601String().substring(0, 10),
      'update_stock': updateStock,
      if (billNo != null && billNo.isNotEmpty) 'bill_no': billNo,
      if (namingSeries != null && namingSeries.isNotEmpty)
        'naming_series': namingSeries,
      if (setWarehouse != null && setWarehouse.isNotEmpty)
        'set_warehouse': setWarehouse,
      if (costCenter != null && costCenter.isNotEmpty)
        'cost_center': costCenter,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Invoice Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'rate': item['rate'] ?? 0,
              'warehouse': item['warehouse'] ?? setWarehouse ?? '',
              'purchase_order': purchaseOrder,
              'po_detail': item['purchase_order_item'],
              if (_validUom(item['uom'])) 'uom': item['uom'],
            },
          )
          .toList(),
    };
    final taxes =
        taxesAndCharges ??
        await _resolvePurchaseInvoiceTaxes(purchaseOrder: purchaseOrder);
    if (taxes != null && taxes.isNotEmpty) doc['taxes_and_charges'] = taxes;

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Invoice',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error creando factura');
  }

  /// Hace submit de un Purchase Invoice (borrador → enviado).
  Future<Map<String, dynamic>> submitPurchaseInvoice(String name) async {
    try {
      final docResponse = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Invoice/${Uri.encodeComponent(name)}',
      );
      if (docResponse.statusCode != 200 || docResponse.data?['data'] == null) {
        throw Exception('No se pudo obtener la factura $name para enviar');
      }
      final Map<String, dynamic> doc = docResponse.data['data'];

      final response = await _dio.post(
        '$baseUrl/api/method/frappe.client.submit',
        data: {'doctype': 'Purchase Invoice', 'docname': name, 'doc': doc},
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw _erpResponseError(response, 'Error enviando factura');
    } on DioException catch (e) {
      throw _erpError(e, 'Error enviando factura');
    }
  }

  /// Lista Purchase Invoices vinculadas a una Purchase Order específica.
  Future<List<Map<String, dynamic>>> listPurchaseInvoicesForPO(
    String poName,
  ) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Purchase Invoice',
          'fields':
              '["name","supplier","posting_date","docstatus","grand_total","status"]',
          'filters': jsonEncode([
            ['Purchase Invoice Item', 'purchase_order', '=', poName],
          ]),
          'group_by': 'name',
          'order_by': 'creation desc',
          'limit_page_length': 50,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listPurchaseInvoicesForPO error: $e');
      return [];
    }
  }

  /// Extrae el detalle del cuerpo de error del ERP.
  String _erpDetail(dynamic data) {
    if (data == null) return '';
    if (data is Map) {
      return (data['exc'] ??
              data['_server_messages'] ??
              data['message'] ??
              data.toString())
          .toString();
    }
    return data.toString();
  }

  /// Sin permisos: 403 o el server menciona PermissionError / Not permitted.
  bool _esErrorPermiso(int? statusCode, String detail) {
    return statusCode == 403 ||
        detail.contains('PermissionError') ||
        detail.contains('Not permitted') ||
        detail.contains('InsufficientPermission');
  }

  /// Normaliza el error del ERP (DioException) a un mensaje legible.
  Exception _erpError(DioException e, String fallback) {
    final detail = _erpDetail(e.response?.data);
    if (_esErrorPermiso(e.response?.statusCode, detail)) {
      return Exception(_msgSinPermiso);
    }
    if (detail.isNotEmpty) {
      return Exception('Servidor: $detail');
    }
    return Exception(
      '$fallback — HTTP ${e.response?.statusCode}: ${e.message}',
    );
  }

  /// Normaliza una respuesta fallida (validateStatus deja pasar 4xx).
  Exception _erpResponseError(Response response, String fallback) {
    final detail = _erpDetail(response.data);
    if (_esErrorPermiso(response.statusCode, detail)) {
      return Exception(_msgSinPermiso);
    }
    if (detail.isNotEmpty) {
      return Exception('Servidor: $detail');
    }
    return Exception('$fallback — HTTP ${response.statusCode}');
  }

  static const _msgSinPermiso =
      'No tenés permisos para realizar esta operación en el ERP — '
      'pedile al administrador que te asigne el rol necesario.';

  /// Obtiene una Purchase Order por nombre.
  Future<Map<String, dynamic>?> getPurchaseOrder(String name) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(name)}',
      );
      if (response.statusCode == 200) {
        return response.data?['data'];
      }
      return null;
    } catch (e) {
      print('[Service] getPurchaseOrder error: $e');
      return null;
    }
  }

  /// Lista Purchase Orders con filtros. Trae el estado real del ERP
  /// (status, per_billed, per_received) para mostrar el ciclo de vida completo.
  Future<List<Map<String, dynamic>>> listPurchaseOrders({
    String? status,
    int limit = 50,
  }) async {
    try {
      List<dynamic> filters = [];
      if (status != null && status.isNotEmpty) {
        filters.add(['docstatus', '=', status == 'Borrador' ? 0 : 1]);
      }

      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Purchase Order',
          'fields':
              '["name","supplier","transaction_date","docstatus","grand_total","status","per_billed","per_received"]',
          'filters': jsonEncode(filters),
          'order_by': 'creation desc',
          'limit_page_length': limit,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listPurchaseOrders error: $e');
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════
  // RECEPCIÓN DE MERCADERÍA (Stock Entry — Material Receipt)
  // ══════════════════════════════════════════════════════════════

  /// Lista Purchase Receipts (recepciones de mercadería desde PO).
  Future<List<Map<String, dynamic>>> listMaterialReceipts({
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Purchase Receipt',
          'fields':
              '["name","supplier","posting_date","docstatus","grand_total","status","per_billed"]',
          'order_by': 'creation desc',
          'limit_page_length': limit,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listMaterialReceipts error: $e');
      return [];
    }
  }

  /// Obtiene los items de un Purchase Receipt enviado (con billed_qty
  /// para calcular el pendiente de facturar).
  Future<List<Map<String, dynamic>>> getPurchaseReceiptItems(
    String prName,
  ) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Receipt/${Uri.encodeComponent(prName)}',
        queryParameters: {
          'fields': '["items","supplier","set_warehouse","cost_center"]',
        },
      );
      if (response.statusCode == 200) {
        final data = response.data?['data'];
        final items = data?['items'] ?? [];
        for (final it in List<Map<String, dynamic>>.from(items)) {
          it['supplier'] = data['supplier'] ?? '';
          it['set_warehouse'] = data['set_warehouse'] ?? '';
          it['cost_center'] = data['cost_center'] ?? '';
        }
        return List<Map<String, dynamic>>.from(items);
      }
      return [];
    } catch (e) {
      print('[Service] getPurchaseReceiptItems error: $e');
      return [];
    }
  }

  /// Obtiene el estado real de un Purchase Receipt desde el ERP
  /// (status + per_billed — el servidor es la única fuente de verdad).
  Future<Map<String, dynamic>> refreshPurchaseReceiptStatus(String name) async {
    final response = await _dio.get(
      '$baseUrl/api/resource/Purchase%20Receipt/${Uri.encodeComponent(name)}',
      queryParameters: {
        'fields': '["name","status","docstatus","per_billed","grand_total"]',
      },
    );
    if (response.statusCode == 200 && response.data?['data'] != null) {
      return Map<String, dynamic>.from(response.data['data']);
    }
    throw Exception('No se pudo leer el estado de la recepción $name');
  }

  /// Resuelve la plantilla de impuestos para una Purchase Invoice heredando
  /// del documento fuente (recepción u orden) — igual que hace el mapper del
  /// ERP al facturar desde la UI. Fallback: plantilla default de la compañía.
  Future<String?> _resolvePurchaseInvoiceTaxes({
    String? purchaseReceipt,
    String? purchaseOrder,
  }) async {
    try {
      if (purchaseReceipt != null && purchaseReceipt.isNotEmpty) {
        final r = await _dio.get(
          '$baseUrl/api/resource/Purchase%20Receipt/${Uri.encodeComponent(purchaseReceipt)}',
          queryParameters: {'fields': '["taxes_and_charges"]'},
        );
        final t = r.data?['data']?['taxes_and_charges']?.toString();
        if (t != null && t.isNotEmpty) return t;
      }
      if (purchaseOrder != null && purchaseOrder.isNotEmpty) {
        final r = await _dio.get(
          '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(purchaseOrder)}',
          queryParameters: {'fields': '["taxes_and_charges"]'},
        );
        final t = r.data?['data']?['taxes_and_charges']?.toString();
        if (t != null && t.isNotEmpty) return t;
      }
    } catch (e) {
      print('[Service] _resolvePurchaseInvoiceTaxes error: $e');
    }
    return _getDefaultPurchaseTaxTemplate();
  }

  /// Crea un Purchase Invoice como borrador desde un Purchase Receipt enviado.
  /// Los items deben traer item_code, qty, rate, name (pr_detail) y warehouse
  /// para que el ERP vincule la factura con la recepción.
  /// [updateStock] en false porque el stock ya lo actualizó la recepción —
  /// marcarlo duplicaría el inventario.
  Future<Map<String, dynamic>> createPurchaseInvoiceFromReceipt({
    required String purchaseReceipt,
    required String supplier,
    required List<Map<String, dynamic>> items,
    String? taxesAndCharges,
    String? costCenter,
    String? setWarehouse,
    String? billNo,
    String? namingSeries,
    bool updateStock = false,
  }) async {
    final doc = {
      'doctype': 'Purchase Invoice',
      'supplier': supplier,
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      'bill_date': DateTime.now().toIso8601String().substring(0, 10),
      'update_stock': updateStock,
      if (billNo != null && billNo.isNotEmpty) 'bill_no': billNo,
      if (namingSeries != null && namingSeries.isNotEmpty)
        'naming_series': namingSeries,
      if (setWarehouse != null && setWarehouse.isNotEmpty)
        'set_warehouse': setWarehouse,
      if (costCenter != null && costCenter.isNotEmpty)
        'cost_center': costCenter,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Invoice Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'rate': item['rate'] ?? 0,
              'warehouse': item['warehouse'] ?? setWarehouse ?? '',
              'purchase_receipt': purchaseReceipt,
              'pr_detail': item['name'],
              if (_validUom(item['uom'])) 'uom': item['uom'],
            },
          )
          .toList(),
    };
    final taxes =
        taxesAndCharges ??
        await _resolvePurchaseInvoiceTaxes(purchaseReceipt: purchaseReceipt);
    if (taxes != null && taxes.isNotEmpty) doc['taxes_and_charges'] = taxes;

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Invoice',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error creando factura');
  }

  /// Crea un Purchase Invoice como borrador SIN orden ni recepción vinculada
  /// (creación directa). Con update_stock en true, la factura misma mueve stock.
  Future<Map<String, dynamic>> createDirectPurchaseInvoice({
    required String supplier,
    required List<Map<String, dynamic>> items,
    String? billNo,
    String? namingSeries,
    String? setWarehouse,
    String? costCenter,
    bool updateStock = true,
    String? taxesAndCharges,
  }) async {
    // Sin documento fuente: hereda la default de la compañía (mismo
    // comportamiento que el UI del ERP al crear una factura directa).
    final taxes = taxesAndCharges ?? await _resolvePurchaseInvoiceTaxes();
    final doc = {
      if (taxes != null && taxes.isNotEmpty) 'taxes_and_charges': taxes,
      'doctype': 'Purchase Invoice',
      'supplier': supplier,
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      'bill_date': DateTime.now().toIso8601String().substring(0, 10),
      'update_stock': updateStock,
      if (billNo != null && billNo.isNotEmpty) 'bill_no': billNo,
      if (namingSeries != null && namingSeries.isNotEmpty)
        'naming_series': namingSeries,
      if (setWarehouse != null && setWarehouse.isNotEmpty)
        'set_warehouse': setWarehouse,
      if (costCenter != null && costCenter.isNotEmpty)
        'cost_center': costCenter,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Invoice Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'rate': item['rate'] ?? 0,
              'warehouse': item['warehouse'] ?? setWarehouse ?? '',
              if (_validUom(item['uom'])) 'uom': item['uom'],
            },
          )
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Invoice',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error creando factura');
  }

  /// Actualiza un Purchase Invoice borrador existente (items + bill_no).
  Future<Map<String, dynamic>> updatePurchaseInvoice({
    required String name,
    required List<Map<String, dynamic>> items,
    String? billNo,
    bool? updateStock,
  }) async {
    final doc = {
      'bill_no': ?billNo,
      'update_stock': ?updateStock,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Invoice Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'rate': item['rate'] ?? 0,
              'warehouse': item['warehouse'] ?? '',
              if (item['purchase_order'] != null)
                'purchase_order': item['purchase_order'],
              if (item['po_detail'] != null) 'po_detail': item['po_detail'],
              if (item['purchase_receipt'] != null)
                'purchase_receipt': item['purchase_receipt'],
              if (item['pr_detail'] != null) 'pr_detail': item['pr_detail'],
              if (_validUom(item['uom'])) 'uom': item['uom'],
            },
          )
          .toList(),
    };

    final response = await _dio.put(
      '$baseUrl/api/resource/Purchase%20Invoice/${Uri.encodeComponent(name)}',
      data: doc,
    );

    if (response.statusCode == 200) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error actualizando factura');
  }

  /// Obtiene un Purchase Invoice por nombre.
  Future<Map<String, dynamic>?> getPurchaseInvoice(String name) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Invoice/${Uri.encodeComponent(name)}',
      );
      if (response.statusCode == 200) {
        return response.data?['data'];
      }
      return null;
    } catch (e) {
      print('[Service] getPurchaseInvoice error: $e');
      return null;
    }
  }

  /// Lista Purchase Invoices con filtros. Trae bill_no y el estado real del ERP.
  Future<List<Map<String, dynamic>>> listPurchaseInvoices({
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Purchase Invoice',
          'fields':
              '["name","supplier","posting_date","docstatus","grand_total","status","bill_no","update_stock"]',
          'order_by': 'creation desc',
          'limit_page_length': limit,
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listPurchaseInvoices error: $e');
      return [];
    }
  }

  /// Lista Purchase Orders enviadas (docstatus=1) para crear recepción desde PO.
  Future<List<Map<String, dynamic>>> listSubmittedPurchaseOrders({
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Purchase Order',
          'fields': '["name","supplier","transaction_date","grand_total"]',
          'filters': '[["docstatus","=",1]]',
          'order_by': 'creation desc',
          'limit_page_length': limit,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listSubmittedPurchaseOrders error: $e');
      return [];
    }
  }

  /// Obtiene los items de una Purchase Order enviada.
  Future<List<Map<String, dynamic>>> getPurchaseOrderItems(
    String poName,
  ) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(poName)}',
        queryParameters: {'fields': '["items"]'},
      );
      if (response.statusCode == 200) {
        final items = response.data?['data']?['items'] ?? [];
        return List<Map<String, dynamic>>.from(items);
      }
      return [];
    } catch (e) {
      print('[Service] getPurchaseOrderItems error: $e');
      return [];
    }
  }

  /// Obtiene el detalle de una PO para pre-llenar el modal de nueva recepción.
  /// Retorna null si no se encuentra la PO.
  Future<Map<String, dynamic>?> getPODetailsForNewReceipt(String poName) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(poName)}',
        queryParameters: {
          'fields': '["name","supplier","set_warehouse","cost_center"]',
        },
      );
      if (response.statusCode == 200) {
        return response.data?['data'];
      }
      return null;
    } catch (e) {
      print('[Service] getPODetailsForNewReceipt error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PURCHASE RECEIPT
  // ══════════════════════════════════════════════════════════════

  /// Obtiene el detalle completo de una Purchase Order (para crear PR).
  Future<Map<String, dynamic>?> getPurchaseOrderDetail(String poName) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(poName)}',
      );
      if (response.statusCode == 200) {
        return response.data?['data'];
      }
      return null;
    } catch (e) {
      print('[Service] getPurchaseOrderDetail error: $e');
      return null;
    }
  }

  /// Obtiene las naming_series disponibles para Purchase Receipt.
  Future<List<String>> fetchPurchaseReceiptNamingSeries() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.desk.form.load.getdoctype',
        queryParameters: {'doctype': 'Purchase Receipt'},
      );
      if (response.statusCode == 200) {
        final docs = response.data?['docs'];
        if (docs is List && docs.isNotEmpty) {
          for (final doc in docs) {
            if (doc is Map &&
                doc['doctype'] == 'DocType' &&
                doc['name'] == 'Purchase Receipt') {
              // Buscar campo naming_series dentro del array fields
              final fields = doc['fields'];
              if (fields is List) {
                for (final f in fields) {
                  if (f is Map && f['fieldname'] == 'naming_series') {
                    final raw = f['options']?.toString() ?? '';
                    final opts = _parseNamingOptions(raw);
                    if (opts.isNotEmpty) return opts;
                  }
                }
              }
            }
          }
        }
      }
      return [];
    } catch (e) {
      print('[Service] fetchPurchaseReceiptNamingSeries error: $e');
      return [];
    }
  }

  /// Crea un Purchase Receipt como borrador SIN PO vinculada (creación directa).
  Future<Map<String, dynamic>> createDirectPurchaseReceipt({
    required String supplier,
    required String warehouse,
    required List<Map<String, dynamic>> items,
    String? namingSeries,
    String? costCenter,
  }) async {
    final doc = {
      'doctype': 'Purchase Receipt',
      'supplier': supplier,
      'set_warehouse': warehouse,
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      if (namingSeries != null && namingSeries.isNotEmpty)
        'naming_series': namingSeries,
      if (costCenter != null && costCenter.isNotEmpty)
        'cost_center': costCenter,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Receipt Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'warehouse': warehouse,
              if (_validUom(item['uom'])) 'uom': item['uom'],
            },
          )
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Receipt',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error creando recepción');
  }

  /// Crea un Purchase Receipt como borrador desde una PO.
  Future<Map<String, dynamic>> createPurchaseReceipt({
    required String purchaseOrder,
    required String supplier,
    required String warehouse,
    required List<Map<String, dynamic>> items,
    String? namingSeries,
    String? costCenter,
    String? taxesAndCharges,
  }) async {
    final doc = {
      'doctype': 'Purchase Receipt',
      'supplier': supplier,
      'set_warehouse': warehouse,
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      if (namingSeries != null && namingSeries.isNotEmpty)
        'naming_series': namingSeries,
      if (costCenter != null && costCenter.isNotEmpty)
        'cost_center': costCenter,
      // Heredar la plantilla de impuestos de la PO (el mapper del UI del ERP
      // la copia al crear PR desde PO; vía API hay que mandarla explícita
      // para que el servidor expanda la tabla taxes).
      if (taxesAndCharges != null && taxesAndCharges.isNotEmpty)
        'taxes_and_charges': taxesAndCharges,
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Receipt Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'warehouse': warehouse,
              'purchase_order': purchaseOrder,
              'purchase_order_item': item['purchase_order_item'],
              if (_validUom(item['uom'])) 'uom': item['uom'],
              if (item['rate'] != null) 'rate': item['rate'],
              if (item['price_list_rate'] != null &&
                  (item['price_list_rate'] as num) > 0)
                'price_list_rate': item['price_list_rate'],
              if (item['net_amount'] != null && (item['net_amount'] as num) > 0)
                'net_amount': item['net_amount'],
            },
          )
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Receipt',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error creando recepción');
  }

  /// Actualiza un Purchase Receipt borrador existente.
  /// [purchaseOrder] se reenvía en cada ítem porque el PUT reemplaza la tabla:
  /// si los items locales no traen la key, el link con la PO se pierde.
  Future<Map<String, dynamic>> updatePurchaseReceipt({
    required String name,
    required List<Map<String, dynamic>> items,
    String? purchaseOrder,
  }) async {
    final doc = {
      'items': items
          .map(
            (item) => {
              'doctype': 'Purchase Receipt Item',
              'item_code': item['item_code'],
              'qty': item['qty'],
              'warehouse': item['warehouse'],
              if ((item['purchase_order'] as String? ?? '').isNotEmpty)
                'purchase_order': item['purchase_order']
              else if (purchaseOrder != null && purchaseOrder.isNotEmpty)
                'purchase_order': purchaseOrder,
              if (item['purchase_order_item'] != null)
                'purchase_order_item': item['purchase_order_item'],
              if (_validUom(item['uom'])) 'uom': item['uom'],
              if (item['rate'] != null) 'rate': item['rate'],
              if (item['price_list_rate'] != null &&
                  (item['price_list_rate'] as num) > 0)
                'price_list_rate': item['price_list_rate'],
              if (item['net_amount'] != null && (item['net_amount'] as num) > 0)
                'net_amount': item['net_amount'],
            },
          )
          .toList(),
    };

    final response = await _dio.put(
      '$baseUrl/api/resource/Purchase%20Receipt/${Uri.encodeComponent(name)}',
      data: doc,
    );

    if (response.statusCode == 200) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error actualizando recepción');
  }

  /// Hace submit de un Purchase Receipt.
  Future<Map<String, dynamic>> submitPurchaseReceipt(String name) async {
    try {
      final docResponse = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Receipt/${Uri.encodeComponent(name)}',
      );
      if (docResponse.statusCode != 200 || docResponse.data?['data'] == null) {
        throw Exception('No se pudo obtener el PR $name para enviar');
      }
      final Map<String, dynamic> doc = docResponse.data['data'];

      final response = await _dio.post(
        '$baseUrl/api/method/frappe.client.submit',
        data: {'doctype': 'Purchase Receipt', 'docname': name, 'doc': doc},
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw _erpResponseError(response, 'Error enviando recepción');
    } on DioException catch (e) {
      throw _erpError(e, 'Error enviando registro');
    }
  }

  /// Lista Purchase Receipts vinculados a una Purchase Order específica.
  Future<List<Map<String, dynamic>>> listPurchaseReceiptsForPO(
    String poName,
  ) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Purchase Receipt',
          'fields':
              '["name","supplier","posting_date","docstatus","grand_total"]',
          'filters': jsonEncode([
            ['Purchase Receipt Item', 'purchase_order', '=', poName],
          ]),
          'group_by': 'name',
          'order_by': 'creation desc',
          'limit_page_length': 50,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listPurchaseReceiptsForPO error: $e');
      return [];
    }
  }

  /// Lista Purchase Receipts existentes.
  Future<List<Map<String, dynamic>>> listPurchaseReceipts({
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Purchase Receipt',
          'fields':
              '["name","supplier","posting_date","docstatus","grand_total"]',
          'order_by': 'creation desc',
          'limit_page_length': limit,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listPurchaseReceipts error: $e');
      return [];
    }
  }

  /// Obtiene el detalle completo de una Purchase Receipt por nombre.
  Future<Map<String, dynamic>?> getPurchaseReceipt(String name) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Receipt/${Uri.encodeComponent(name)}',
      );
      if (response.statusCode == 200) {
        return response.data?['data'];
      }
      return null;
    } catch (e) {
      print('[Service] getPurchaseReceipt error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PLANTILLA DE IMPUESTOS DE COMPRA
  // ══════════════════════════════════════════════════════════════

  /// Devuelve la plantilla de impuestos de compra default de la company
  /// (Purchase Taxes and Charges Template con is_default=1), cacheada.
  /// Es la misma que el UI del ERP aplica al crear la orden; por API hay que
  /// mandarla explícitamente en `taxes_and_charges` para que el servidor
  /// expanda la tabla `taxes` y resuelva el item_tax_template de cada ítem
  /// (ej. ítems con 18%INCL toman su plantilla del master del ítem).
  Future<String?> _getDefaultPurchaseTaxTemplate() async {
    if (_defaultPurchaseTaxTemplate != null &&
        _defaultPurchaseTaxTemplate!.isNotEmpty) {
      return _defaultPurchaseTaxTemplate;
    }
    try {
      // Resolver la company si todavía no se cacheó (mismo fallback que
      // fetchCompanyCurrency: User del usuario → System Settings).
      String? companyName = _company;
      if (companyName == null || companyName.isEmpty) {
        try {
          final userResponse = await _dio.get(
            '$baseUrl/api/resource/User/${Uri.encodeComponent(_loggedUser)}',
            queryParameters: {'fields': '["company"]'},
          );
          final c = userResponse.data?['data']?['company'];
          if (c != null && c.toString().isNotEmpty) companyName = c.toString();
        } catch (_) {}
      }
      if (companyName == null || companyName.isEmpty) {
        // System Settings requiere rol System Manager (los usuarios comunes
        // reciben {} silencioso en get_value); la lista de Company sí es
        // legible para usuarios normales. Con una sola company (SuperZito)
        // es la resolución correcta.
        try {
          final compRes = await _dio.get(
            '$baseUrl/api/resource/Company',
            queryParameters: {'fields': '["name"]', 'limit_page_length': '0'},
          );
          final List list = compRes.data?['data'] ?? const [];
          if (list.length == 1) {
            final c = list.first['name']?.toString();
            if (c != null && c.isNotEmpty) companyName = c;
          }
        } catch (_) {}
      }
      if (companyName == null || companyName.isEmpty) return null;
      _company = companyName;

      final res = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Taxes%20and%20Charges%20Template',
        queryParameters: {
          'filters': '[["company","=","$companyName"],["is_default","=",1]]',
          'fields': '["name"]',
          'limit_page_length': '1',
        },
      );
      final list = res.data?['data'];
      if (list is List && list.isNotEmpty) {
        final name = list.first['name']?.toString();
        if (name != null && name.isNotEmpty) {
          _defaultPurchaseTaxTemplate = name;
          print('[Service] Plantilla de impuestos de compra default: $name');
        }
      } else {
        print('[Service] Sin plantilla de impuestos default para $companyName');
      }
    } catch (e) {
      print('[Service] Error buscando plantilla de impuestos default: $e');
    }
    return _defaultPurchaseTaxTemplate;
  }

  // ══════════════════════════════════════════════════════════════
  // COMPANY / CURRENCY
  // ══════════════════════════════════════════════════════════════

  /// Obtiene la moneda por defecto de la company del ERPNext.
  /// Primero busca la company del usuario logueado, luego obtiene su moneda.
  Future<String> fetchCompanyCurrency() async {
    // Intento 1: company del usuario logueado
    try {
      final userResponse = await _dio.get(
        '$baseUrl/api/resource/User/${Uri.encodeComponent(_loggedUser)}',
        queryParameters: {'fields': '["company"]'},
      );
      final companyName = userResponse.data?['data']?['company'];
      if (companyName != null && companyName.toString().isNotEmpty) {
        _company ??= companyName.toString();
        final companyResponse = await _dio.get(
          '$baseUrl/api/resource/Company/${Uri.encodeComponent(companyName)}',
          queryParameters: {'fields': '["default_currency"]'},
        );
        final cur = companyResponse.data?['data']?['default_currency'];
        if (cur != null && cur.toString().isNotEmpty) {
          print('[Service] Company currency (User): $cur');
          currency = cur.toString();
          return cur.toString();
        }
      }
    } catch (e) {
      print('[Service] fetchCompanyCurrency (User path) error: $e');
    }

    // Intento 2: default_company del System Settings
    try {
      final sysRes = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_value',
        queryParameters: {
          'doctype': 'System Settings',
          'fieldname': 'default_company',
        },
      );
      final companyName = sysRes.data?['message']?.toString();
      if (companyName != null && companyName.isNotEmpty) {
        _company ??= companyName;
        final companyResponse = await _dio.get(
          '$baseUrl/api/resource/Company/${Uri.encodeComponent(companyName)}',
          queryParameters: {'fields': '["default_currency"]'},
        );
        final cur = companyResponse.data?['data']?['default_currency'];
        if (cur != null && cur.toString().isNotEmpty) {
          print('[Service] Company currency (SystemSettings): $cur');
          currency = cur.toString();
          return cur.toString();
        }
      }
    } catch (e) {
      print('[Service] fetchCompanyCurrency (SysSettings path) error: $e');
    }

    // Intento 3: primera company de la lista
    try {
      final listRes = await _dio.get(
        '$baseUrl/api/resource/Company',
        queryParameters: {
          'fields': '["name","default_currency"]',
          'limit_page_length': '1',
        },
      );
      final items = listRes.data?['data'];
      if (items is List && items.isNotEmpty) {
        final cur = items[0]['default_currency'];
        if (cur != null && cur.toString().isNotEmpty) {
          print('[Service] Company currency (first company): $cur');
          currency = cur.toString();
          return cur.toString();
        }
      }
    } catch (e) {
      print('[Service] fetchCompanyCurrency (fallback list) error: $e');
    }

    return '';
  }

  // ══════════════════════════════════════════════════════════════
  // ENTRADA DE INVENTARIO (Stock Entry)
  // ══════════════════════════════════════════════════════════════

  /// Lista los tipos de Stock Entry desde el ERP (doctype `Stock Entry Type`).
  /// La app solo usa: Material Receipt, Material Transfer y Material Issue.
  Future<List<Map<String, dynamic>>> fetchStockEntryTypes() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Stock Entry Type',
          'fields': '["name","purpose"]',
          'limit_page_length': 20,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        final all = data.cast<Map<String, dynamic>>().toList();
        // Filtrar a los tipos que la app puede armar bien
        final allowed = {
          'Material Receipt',
          'Material Transfer',
          'Material Issue',
        };
        return all.where((t) => allowed.contains(t['name'])).toList();
      }
      return [];
    } catch (e) {
      print('[Service] fetchStockEntryTypes error: $e');
      return [];
    }
  }

  /// Lista Stock Entries existentes.
  Future<List<Map<String, dynamic>>> listStockEntries({int limit = 50}) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Stock Entry',
          'fields':
              '["name","stock_entry_type","posting_date","docstatus","creation"]',
          'order_by': 'creation desc',
          'limit_page_length': limit,
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data?['message'] ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      print('[Service] listStockEntries error: $e');
      return [];
    }
  }

  /// Obtiene el detalle completo de un Stock Entry por nombre.
  Future<Map<String, dynamic>?> getStockEntry(String name) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Stock%20Entry/${Uri.encodeComponent(name)}',
      );
      if (response.statusCode == 200) {
        return response.data?['data'];
      }
      return null;
    } catch (e) {
      print('[Service] getStockEntry error: $e');
      return null;
    }
  }

  /// Crea un Stock Entry como borrador (docstatus=0).
  /// [costCenter] se pega en cada fila de items; los almacenes de la fila
  /// (s_warehouse/t_warehouse) mandan — los de cabecera son solo default.
  Future<Map<String, dynamic>> createStockEntry({
    required String stockEntryType,
    required List<Map<String, dynamic>> items,
    String? sourceWarehouse,
    String? targetWarehouse,
    String? costCenter,
    String? remarks,
    String? namingSeries,
  }) async {
    final doc = {
      'doctype': 'Stock Entry',
      'stock_entry_type': stockEntryType,
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      if (namingSeries != null && namingSeries.isNotEmpty)
        'naming_series': namingSeries,
      if (sourceWarehouse != null && sourceWarehouse.isNotEmpty)
        'from_warehouse': sourceWarehouse,
      // El header del Stock Entry usa 'to_warehouse' (t_warehouse es el
      // campo de la FILA). Con t_warehouse el ERP lo ignora y el destino
      // queda vacío → ValidationError al guardar.
      if (targetWarehouse != null && targetWarehouse.isNotEmpty)
        'to_warehouse': targetWarehouse,
      if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
      if (costCenter != null && costCenter.isNotEmpty)
        'cost_center': costCenter,
      'items': items
          .map(
            (item) => {
              'doctype': 'Stock Entry Detail',
              'item_code': item['item_code'],
              'qty': item['qty'],
              's_warehouse': item['s_warehouse'] ?? sourceWarehouse ?? '',
              't_warehouse': item['t_warehouse'] ?? targetWarehouse ?? '',
              if (costCenter != null && costCenter.isNotEmpty)
                'cost_center': costCenter,
              if (_validUom(item['uom'])) 'uom': item['uom'],
            },
          )
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Stock%20Entry',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error creando entrada de inventario');
  }

  /// Actualiza un Stock Entry borrador existente (items + cabecera).
  Future<Map<String, dynamic>> updateStockEntry({
    required String name,
    required String stockEntryType,
    required List<Map<String, dynamic>> items,
    String? sourceWarehouse,
    String? targetWarehouse,
    String? costCenter,
    String? remarks,
  }) async {
    final doc = {
      'stock_entry_type': stockEntryType,
      'from_warehouse': ?sourceWarehouse,
      // Header del Stock Entry usa 'to_warehouse', no 't_warehouse'.
      'to_warehouse': ?targetWarehouse,
      'remarks': ?remarks,
      'cost_center': ?costCenter,
      'items': items
          .map(
            (item) => {
              'doctype': 'Stock Entry Detail',
              'item_code': item['item_code'],
              'qty': item['qty'],
              's_warehouse': item['s_warehouse'] ?? sourceWarehouse ?? '',
              't_warehouse': item['t_warehouse'] ?? targetWarehouse ?? '',
              if (costCenter != null && costCenter.isNotEmpty)
                'cost_center': costCenter,
              if (_validUom(item['uom'])) 'uom': item['uom'],
            },
          )
          .toList(),
    };

    final response = await _dio.put(
      '$baseUrl/api/resource/Stock%20Entry/${Uri.encodeComponent(name)}',
      data: doc,
    );

    if (response.statusCode == 200) {
      return response.data['data'] ?? {};
    }
    throw _erpResponseError(response, 'Error actualizando entrada de inventario');
  }

  /// Hace submit de un Stock Entry (docstatus 0 → 1).
  Future<Map<String, dynamic>> submitStockEntry(String name) async {
    try {
      final docResponse = await _dio.get(
        '$baseUrl/api/resource/Stock%20Entry/${Uri.encodeComponent(name)}',
      );
      if (docResponse.statusCode != 200 || docResponse.data?['data'] == null) {
        throw Exception('No se pudo obtener el Stock Entry $name para enviar');
      }
      final Map<String, dynamic> doc = docResponse.data['data'];

      final response = await _dio.post(
        '$baseUrl/api/method/frappe.client.submit',
        data: {'doctype': 'Stock Entry', 'docname': name, 'doc': doc},
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw _erpResponseError(response, 'Error enviando entrada de inventario');
    } on DioException catch (e) {
      throw _erpError(e, 'Error enviando registro');
    }
  }

  /// Obtiene las naming_series disponibles para Stock Entry.
  Future<List<String>> fetchStockEntryNamingSeries() async {
    return await fetchNamingSeries('Stock Entry');
  }

  // ══════════════════════════════════════════════════════════════
  // ETIQUETAS DE PRECIO (módulo etiquetas)
  // ══════════════════════════════════════════════════════════════

  /// Lista las listas de precios activas (para el selector de configuración).
  Future<List<String>> fetchPriceLists() async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Price List',
          'fields': '["name","currency"]',
          'filters': '[["enabled","=",1],["selling","=",1]]',
          'limit_page_length': 0,
        },
      );
      if (response.statusCode != 200) return [];
      final List<dynamic> rows = response.data?['message'] ?? [];
      final lists = rows
          .map((r) => (r['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toList()
        ..sort();
      return lists;
    } catch (_) {
      return [];
    }
  }

  /// Trae el precio de venta de un item en una lista de precios (Item Price).
  /// Retorna null si el item no tiene precio en esa lista.
  Future<double?> fetchItemPrice({
    required String itemCode,
    required String priceList,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Item Price',
          'fields': '["price_list_rate"]',
          'filters':
              '[["item_code","=","$itemCode"],["price_list","=","$priceList"],["selling","=",1]]',
          'limit_page_length': 1,
          'order_by': 'valid_from desc, modified desc',
        },
      );
      if (response.statusCode != 200) return null;
      final List<dynamic> rows = response.data?['message'] ?? [];
      if (rows.isEmpty) return null;
      final rate = rows[0]['price_list_rate'];
      if (rate is num) return rate.toDouble();
      return double.tryParse(rate.toString());
    } catch (_) {
      return null;
    }
  }

  /// Trae los precios de varios items de golpe (Item Price) en la lista dada.
  /// Retorna mapa item_code → precio. Los items sin precio no aparecen.
  Future<Map<String, double>> fetchItemPrices({
    required List<String> itemCodes,
    required String priceList,
  }) async {
    final result = <String, double>{};
    if (itemCodes.isEmpty || priceList.isEmpty) return result;
    try {
      // En chunks de 50 para no pasarnos del largo de la URL.
      for (var i = 0; i < itemCodes.length; i += 50) {
        final chunk = itemCodes.skip(i).take(50).toList();
        final codesJson = chunk
            .map((c) => '"${c.replaceAll('"', '')}"')
            .join(',');
        final response = await _dio.get(
          '$baseUrl/api/method/frappe.client.get_list',
          queryParameters: {
            'doctype': 'Item Price',
            'fields': '["item_code","price_list_rate"]',
            'filters':
                '[["item_code","in",[$codesJson]],["price_list","=","$priceList"],["selling","=",1]]',
            'limit_page_length': 0,
          },
        );
        if (response.statusCode != 200) continue;
        final List<dynamic> rows = response.data?['message'] ?? [];
        for (final row in rows) {
          final code = (row['item_code'] ?? '').toString().toUpperCase();
          final rate = row['price_list_rate'];
          if (code.isNotEmpty && rate is num) {
            result[code] = rate.toDouble();
          }
        }
      }
    } catch (_) {}
    return result;
  }

  // ══════════════════════════════════════════════════════════════
  // PLANTILLA DE ETIQUETAS (sincronizada como File JSON en el ERP)
  //
  // El diseño vive en el ERP (un File con nombre fijo) para que todos
  // los dispositivos usen la misma plantilla. No requiere doctype nuevo
  // ni permisos de admin: cualquier usuario con sesión puede subir /
  // descargar el archivo.
  // ══════════════════════════════════════════════════════════════

  static const String labelTemplateFileName = 'scanzapp_label_template.json';
  static const String labelTemplateFolder = 'Home';

  /// Busca el File de la plantilla y retorna su name, o null si no existe.
  Future<String?> _findLabelTemplateFile() async {
    try {
      final res = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'File',
          'fields': '["name"]',
          'filters':
              '[["file_name","=","$labelTemplateFileName"],["is_folder","=",0]]',
          'order_by': 'creation desc',
          'limit_page_length': 1,
        },
      );
      if (res.statusCode != 200) return null;
      final rows = res.data?['message'];
      if (rows is! List || rows.isEmpty) return null;
      final name = rows.first['name']?.toString() ?? '';
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  /// Descarga la plantilla de etiquetas del ERP.
  /// Retorna el JSON como String, o null si todavía no existe en el ERP.
  Future<String?> fetchLabelTemplate() async {
    final name = await _findLabelTemplateFile();
    if (name == null) return null;
    try {
      final res = await _dio.get(
        '$baseUrl/api/resource/File/${Uri.encodeComponent(name)}',
        queryParameters: {'fields': '["content"]'},
      );
      if (res.statusCode != 200) return null;
      final data = res.data?['data'];
      final content = data is Map ? data['content'] : null;
      if (content is String && content.trim().isNotEmpty) return content;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sube (o actualiza, sin duplicar) la plantilla de etiquetas al ERP.
  Future<void> uploadLabelTemplate(String jsonStr) async {
    final existing = await _findLabelTemplateFile();
    if (existing != null) {
      final res = await _dio.put(
        '$baseUrl/api/resource/File/${Uri.encodeComponent(existing)}',
        data: {'content': jsonStr},
      );
      if (res.statusCode == 200) return;
      throw Exception(
          'No se pudo actualizar la plantilla en el ERP (${res.statusCode})');
    }
    final res = await _dio.post(
      '$baseUrl/api/resource/File',
      data: {
        'doctype': 'File',
        'file_name': labelTemplateFileName,
        'folder': labelTemplateFolder,
        'is_private': 0,
        'content': jsonStr,
      },
    );
    if (res.statusCode != 200) {
      throw Exception(
          'No se pudo subir la plantilla al ERP (${res.statusCode})');
    }
  }
}
