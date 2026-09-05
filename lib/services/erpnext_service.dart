import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cookie_jar/cookie_jar.dart';
import '../models/item_model.dart';

/// Servicio para conectarse a la API REST de ERPNext/Frappe.
/// Versión Mobile — usa autenticación por sesión (usuario/contraseña).
class ErpNextService {
  String baseUrl = '';
  String _username = '';
  String _password = '';

  late final Dio _dio;
  late final CookieJar _cookieJar;
  String _loggedUser = '';

  String get loggedUser => _loggedUser;
  String get username => _username;

  ErpNextService() {
    _cookieJar = CookieJar();
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      validateStatus: (status) => status != null && status < 500,
    ));
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
        data: {
          'usr': _username,
          'pwd': _password,
        },
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

  /// Obtiene TODOS los productos con stock, incluyendo barcodes secundarios.
  Future<({List<ItemModel> items, Map<String, String> barcodeMap})> fetchAllItemsAndBarcodes({
    void Function(int loaded, int? total)? onProgress,
  }) async {
    onProgress?.call(0, null);

    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Item',
          'fields': '["name","item_code","item_name","stock_uom","barcodes.barcode"]',
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
        queryParameters: {
          'text': code.trim(),
        },
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

    final response = await _dio.post(
      '$baseUrl/api/resource/Item',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw Exception('Error creando item: ${response.data}');
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
          .map((item) => {
                'doctype': 'Stock Reconciliation Item',
                'item_code': item['item_code'],
                'warehouse': warehouse,
                'qty_after_transaction': item['quantity'],
                'valuation_rate': item['unit_cost'],
              })
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
            if (doc is Map && doc['doctype'] == 'DocType' && doc['name'] == doctype) {
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
        print('[NS] M1 body: ${body.substring(0, body.length > 300 ? 300 : body.length)}');
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
          'filters': jsonEncode([['docstatus', 'in', [0, 1]]]),
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
  }) async {
    final doc = {
      'doctype': 'Purchase Order',
      'supplier': supplier,
      'transaction_date': scheduleDate,
      'schedule_date': scheduleDate,
      'currency': 'HNL',
      if (namingSeries.isNotEmpty) 'naming_series': namingSeries,
      if (costCenter.isNotEmpty) 'cost_center': costCenter,
      if (setWarehouse.isNotEmpty) 'set_warehouse': setWarehouse,
      'items': items
          .map((item) => {
                'doctype': 'Purchase Order Item',
                'item_code': item['item_code'],
                'qty': item['qty'],
                'rate': item['rate'] ?? 0,
                'schedule_date': scheduleDate,
              })
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Order',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw Exception('Error guardando borrador: ${response.data}');
  }

  /// Actualiza un borrador existente en ERPNext (agrega/modifica items).
  Future<Map<String, dynamic>> updatePurchaseOrder({
    required String name,
    required List<Map<String, dynamic>> items,
  }) async {
    final doc = {
      'items': items
          .map((item) => {
                'doctype': 'Purchase Order Item',
                'item_code': item['item_code'],
                'qty': item['qty'],
                'rate': item['rate'] ?? 0,
              })
          .toList(),
    };

    final response = await _dio.put(
      '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(name)}',
      data: doc,
    );

    if (response.statusCode == 200) {
      return response.data['data'] ?? {};
    }
    throw Exception('Error actualizando borrador: ${response.data}');
  }

  /// Hace submit de una Purchase Order borrador (docstatus 0 → 1).
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
        data: {
          'doctype': 'Purchase Order',
          'docname': name,
          'doc': doc,
        },
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw Exception('Error HTTP ${response.statusCode}: ${response.data}');
    } on DioException catch (e) {
      String detail = '';
      if (e.response?.data != null) {
        if (e.response!.data is Map) {
          detail = e.response!.data['exc'] ??
              e.response!.data['_server_messages'] ??
              e.response!.data['message'] ??
              e.response!.data.toString();
        } else {
          detail = e.response!.data.toString();
        }
      }
      if (detail.isNotEmpty) {
        throw Exception('Servidor: $detail');
      }
      throw Exception('Error HTTP ${e.response?.statusCode}: ${e.message}');
    }
  }

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

  /// Lista Purchase Orders con filtros.
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
          'fields': '["name","supplier","transaction_date","docstatus","grand_total"]',
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

  /// Lista Stock Entries tipo "Material Receipt".
  Future<List<Map<String, dynamic>>> listMaterialReceipts({
    int limit = 50,
  }) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/method/frappe.client.get_list',
        queryParameters: {
          'doctype': 'Stock Entry',
          'fields': '["name","posting_date","stock_entry_type","docstatus","total_amount","supplier"]',
          'filters': '[["stock_entry_type","=","Material Receipt"]]',
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

  /// Obtiene un Stock Entry por nombre.
  Future<Map<String, dynamic>?> getMaterialReceipt(String name) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Stock%20Entry/${Uri.encodeComponent(name)}',
      );
      if (response.statusCode == 200) {
        return response.data?['data'];
      }
      return null;
    } catch (e) {
      print('[Service] getMaterialReceipt error: $e');
      return null;
    }
  }

  /// Crea un Stock Entry tipo "Material Receipt" como borrador.
  Future<Map<String, dynamic>> createMaterialReceipt({
    required String warehouse,
    required List<Map<String, dynamic>> items,
    String? namingSeries,
    String? supplier,
  }) async {
    final doc = {
      'doctype': 'Stock Entry',
      'stock_entry_type': 'Material Receipt',
      'posting_date': DateTime.now().toIso8601String().substring(0, 10),
      if (namingSeries != null && namingSeries.isNotEmpty) 'naming_series': namingSeries,
      if (supplier != null && supplier.isNotEmpty) 'supplier': supplier,
      'items': items
          .map((item) => {
                'doctype': 'Stock Entry Detail',
                'item_code': item['item_code'],
                'qty': item['qty'],
                't_warehouse': warehouse,
                if (item['uom'] != null) 'uom': item['uom'],
              })
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Stock%20Entry',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw Exception('Error creando recepción: ${response.data}');
  }

  /// Actualiza un Stock Entry borrador existente.
  Future<Map<String, dynamic>> updateMaterialReceipt({
    required String name,
    required List<Map<String, dynamic>> items,
  }) async {
    final doc = {
      'items': items
          .map((item) => {
                'doctype': 'Stock Entry Detail',
                'item_code': item['item_code'],
                'qty': item['qty'],
                't_warehouse': item['t_warehouse'],
                if (item['uom'] != null) 'uom': item['uom'],
              })
          .toList(),
    };

    final response = await _dio.put(
      '$baseUrl/api/resource/Stock%20Entry/${Uri.encodeComponent(name)}',
      data: doc,
    );

    if (response.statusCode == 200) {
      return response.data['data'] ?? {};
    }
    throw Exception('Error actualizando recepción: ${response.data}');
  }

  /// Hace submit de un Stock Entry (borrador → submitted).
  Future<Map<String, dynamic>> submitMaterialReceipt(String name) async {
    try {
      // Paso 1: Obtener el documento completo
      final docResponse = await _dio.get(
        '$baseUrl/api/resource/Stock%20Entry/${Uri.encodeComponent(name)}',
      );
      if (docResponse.statusCode != 200 || docResponse.data?['data'] == null) {
        throw Exception('No se pudo obtener la recepción $name para enviar');
      }
      final Map<String, dynamic> doc = docResponse.data['data'];

      // Paso 2: Enviar
      final response = await _dio.post(
        '$baseUrl/api/method/frappe.client.submit',
        data: {
          'doctype': 'Stock Entry',
          'docname': name,
          'doc': doc,
        },
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw Exception('Error HTTP ${response.statusCode}: ${response.data}');
    } on DioException catch (e) {
      String detail = '';
      if (e.response?.data != null) {
        if (e.response!.data is Map) {
          detail = e.response!.data['exc'] ??
              e.response!.data['_server_messages'] ??
              e.response!.data['message'] ??
              e.response!.data.toString();
        } else {
          detail = e.response!.data.toString();
        }
      }
      if (detail.isNotEmpty) {
        throw Exception('Servidor: $detail');
      }
      throw Exception('Error HTTP ${e.response?.statusCode}: ${e.message}');
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
  Future<List<Map<String, dynamic>>> getPurchaseOrderItems(String poName) async {
    try {
      final response = await _dio.get(
        '$baseUrl/api/resource/Purchase%20Order/${Uri.encodeComponent(poName)}',
        queryParameters: {
          'fields': '["items"]',
        },
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
            if (doc is Map && doc['name'] == 'Purchase Receipt') {
              if (doc['naming_series'] != null) {
                return List<String>.from(doc['naming_series']);
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

  /// Crea un Purchase Receipt como borrador desde una PO.
  Future<Map<String, dynamic>> createPurchaseReceipt({
    required String purchaseOrder,
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
          .map((item) => {
                'doctype': 'Purchase Receipt Item',
                'item_code': item['item_code'],
                'qty': item['qty'],
                'warehouse': warehouse,
                'purchase_order': purchaseOrder,
                'purchase_order_item': item['purchase_order_item'],
                if (item['uom'] != null) 'uom': item['uom'],
                if (item['rate'] != null) 'rate': item['rate'],
              })
          .toList(),
    };

    final response = await _dio.post(
      '$baseUrl/api/resource/Purchase%20Receipt',
      data: doc,
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return response.data['data'] ?? {};
    }
    throw Exception('Error creando Purchase Receipt: ${response.data}');
  }

  /// Actualiza un Purchase Receipt borrador existente.
  Future<Map<String, dynamic>> updatePurchaseReceipt({
    required String name,
    required List<Map<String, dynamic>> items,
  }) async {
    final doc = {
      'items': items
          .map((item) => {
                'doctype': 'Purchase Receipt Item',
                'item_code': item['item_code'],
                'qty': item['qty'],
                'warehouse': item['warehouse'],
                if (item['purchase_order'] != null)
                  'purchase_order': item['purchase_order'],
                if (item['purchase_order_item'] != null)
                  'purchase_order_item': item['purchase_order_item'],
                if (item['uom'] != null) 'uom': item['uom'],
                if (item['rate'] != null) 'rate': item['rate'],
              })
          .toList(),
    };

    final response = await _dio.put(
      '$baseUrl/api/resource/Purchase%20Receipt/${Uri.encodeComponent(name)}',
      data: doc,
    );

    if (response.statusCode == 200) {
      return response.data['data'] ?? {};
    }
    throw Exception('Error actualizando Purchase Receipt: ${response.data}');
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
        data: {
          'doctype': 'Purchase Receipt',
          'docname': name,
          'doc': doc,
        },
      );
      if (response.statusCode == 200) {
        return response.data['data'] ?? {};
      }
      throw Exception('Error HTTP ${response.statusCode}: ${response.data}');
    } on DioException catch (e) {
      String detail = '';
      if (e.response?.data != null) {
        if (e.response!.data is Map) {
          detail = e.response!.data['exc'] ??
              e.response!.data['_server_messages'] ??
              e.response!.data['message'] ??
              e.response!.data.toString();
        } else {
          detail = e.response!.data.toString();
        }
      }
      if (detail.isNotEmpty) {
        throw Exception('Servidor: $detail');
      }
      throw Exception('Error HTTP ${e.response?.statusCode}: ${e.message}');
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
          'fields': '["name","supplier","posting_date","docstatus","grand_total"]',
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
}
