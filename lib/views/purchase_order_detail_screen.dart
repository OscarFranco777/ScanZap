import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';
import '../services/erpnext_service.dart';
import '../models/purchase_order.dart';
import 'purchase_receipt_detail_screen.dart';

/// Pantalla de creación y detalle de Orden de Compra.
/// Incluye escáner de cámara y entrada manual.
class PurchaseOrderDetailScreen extends StatefulWidget {
  const PurchaseOrderDetailScreen({super.key});

  @override
  State<PurchaseOrderDetailScreen> createState() =>
      _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends State<PurchaseOrderDetailScreen> {
  // ─── Cámara ───
  MobileScannerController? _cameraController;
  bool _cameraActive = true;
  bool _scanLocked = false;
  String _lastScannedCode = '';
  Timer? _lockTimer;

  // ─── Formulario ───
  final _supplierController = TextEditingController();
  String _selectedSupplierId = '';
  final _scanController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _supplierSuggestions = [];
  bool _showForm = true; // Mostrar formulario o escáner

  // ─── Campos nuevos ───
  String _selectedWarehouse = '';
  String _selectedCostCenter = '';
  String _selectedNamingSeries = '';

  // ─── Purchase Receipt (recepción desde PO) ───
  bool _showPRForm = false;
  bool _prLoading = false;
  String _prError = '';
  List<Map<String, dynamic>> _prItems = [];
  String _prWarehouse = '';
  String _prNamingSeries = '';
  List<String> _prNamingSeriesOptions = [];
  bool _prScannerActive = false;
  MobileScannerController? _prCameraController;
  final _prScanController = TextEditingController();
  final _prQtyController = TextEditingController(text: '1');
  bool _prScanLocked = false;
  String _prLastScannedCode = '';
  Timer? _prLockTimer;
  bool _prSaved = false;
  String _prSavedName = '';

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    // Sincronizar caché de items del inventario y catálogos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inventoryProvider = context.read<InventoryProvider>();
      final poProvider = context.read<PurchaseOrderProvider>();
      poProvider.loadItemsCache(inventoryProvider.itemsByCode);
      poProvider.fetchCatalogs();
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _prCameraController?.dispose();
    _lockTimer?.cancel();
    _prLockTimer?.cancel();
    _supplierController.dispose();
    _scanController.dispose();
    _qtyController.dispose();
    _prScanController.dispose();
    _prQtyController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // ESCANEO
  // ══════════════════════════════════════════════════════════════

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_scanLocked) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!.trim();
    if (code.isEmpty || code == _lastScannedCode) return;

    _scanLocked = true;
    _lastScannedCode = code;
    _cameraController?.stop();

    _processScan(code);
  }

  void _processScan(String code) {
    if (code.trim().isEmpty) return;
    HapticFeedback.mediumImpact();

    final provider = context.read<PurchaseOrderProvider>();
    final qty = int.tryParse(_qtyController.text.trim()) ?? 1;
    provider.scanItemToOrder(code, quantity: qty);
    _qtyController.text = '1';
    _scanController.clear();

    _lockTimer?.cancel();
    _lockTimer = Timer(const Duration(seconds: 2), () {
      _scanLocked = false;
      _lastScannedCode = '';
      if (_cameraActive && mounted) {
        _cameraController?.start();
      }
    });
  }

  // ══════════════════════════════════════════════════════════════
  // ACCIONES
  // ══════════════════════════════════════════════════════════════

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _searchSuppliers(String query) async {
    if (query.length < 2) {
      setState(() => _supplierSuggestions = []);
      return;
    }
    final provider = context.read<PurchaseOrderProvider>();
    final results = await provider.searchSuppliers(query);
    if (mounted) {
      setState(() => _supplierSuggestions = results);
    }
  }

  void _createOrder() {
    if (_supplierController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Seleccioná un proveedor'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedWarehouse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Seleccioná un almacén destino'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedCostCenter.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Seleccioná un centro de costos'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Usar la serie seleccionada, o la primera de la lista como default
    final provider = context.read<PurchaseOrderProvider>();
    final namingSeries = _selectedNamingSeries.isNotEmpty
        ? _selectedNamingSeries
        : (provider.namingSeriesOptions.isNotEmpty
              ? provider.namingSeriesOptions.first
              : '');

    provider.createNewOrder(
      supplier: _supplierController.text.trim(),
      supplierId: _selectedSupplierId,
      date: _selectedDate,
      costCenter: _selectedCostCenter,
      setWarehouse: _selectedWarehouse,
      namingSeries: namingSeries,
    );

    setState(() => _showForm = false);
  }

  Future<void> _saveOrder() async {
    final provider = context.read<PurchaseOrderProvider>();
    final ok = await provider.saveOrder();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💾 Borrador guardado: ${provider.currentOrder?.id ?? ''}',
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
      // No hacemos pop aquí porque el usuario sigue editando
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${provider.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitOrder() async {
    final provider = context.read<PurchaseOrderProvider>();

    if (!provider.isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Primero guardá la orden como borrador'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Confirmar antes de enviar
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar orden'),
        content: const Text(
          '¿Confirmás que querés enviar esta orden a ERPNext? No podrá modificarse después.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final ok = await provider.submitOrder();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Orden ${provider.currentOrder?.id ?? ''} enviada'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true); // Señal para refrescar lista
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${provider.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PURCHASE RECEIPT (recepción desde PO)
  // ══════════════════════════════════════════════════════════════

  /// Abre el formulario de creación de Purchase Receipt desde la PO.
  Future<void> _openPRForm() async {
    final provider = context.read<PurchaseOrderProvider>();
    final order = provider.currentOrder;
    if (order == null || order.id == null) return;

    setState(() {
      _showPRForm = true;
      _prLoading = true;
      _prError = '';
      _prItems = [];
      _prWarehouse = order.setWarehouse;
      _prSaved = false;
      _prSavedName = '';
    });

    try {
      final service = context.read<ErpNextService>();

      // Obtener detalle de la PO y naming series en paralelo
      final results = await Future.wait([
        service.getPurchaseOrderDetail(order.id!),
        service.fetchPurchaseReceiptNamingSeries(),
      ]);

      final poDetail = results[0] as Map<String, dynamic>?;
      final series = results[1] as List<String>;

      if (poDetail != null && poDetail['items'] != null) {
        final items = List<Map<String, dynamic>>.from(poDetail['items']);
        _prItems = items.map((item) => {
          'item_code': item['item_code'] ?? '',
          'item_name': item['item_name'] ?? '',
          'qty': item['qty'] ?? 0,
          'received_qty': item['received_qty'] ?? 0,
          'uom': item['uom'] ?? 'Unidad',
          'rate': item['rate'] ?? 0,
          'purchase_order_item': item['name'] ?? '',
        }).toList();
      }

      _prNamingSeriesOptions = series;
      if (series.isNotEmpty) _prNamingSeries = series.first;
    } catch (e) {
      _prError = 'Error cargando datos: $e';
    }

    setState(() => _prLoading = false);
  }

  /// Procesa un escaneo en el formulario de PR.
  void _onPRBarcodeDetected(BarcodeCapture capture) {
    if (_prScanLocked) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!.trim();
    if (code.isEmpty || code == _prLastScannedCode) return;

    _prScanLocked = true;
    _prLastScannedCode = code;
    _prCameraController?.stop();
    _processPRScan(code);
  }

  void _processPRScan(String code) {
    if (code.trim().isEmpty) return;
    HapticFeedback.mediumImpact();

    final qty = int.tryParse(_prQtyController.text.trim()) ?? 1;
    final cleanCode = code.trim().toUpperCase();

    // Buscar si ya está en la lista
    final existingIndex = _prItems.indexWhere(
      (i) => (i['item_code'] ?? '').toString().toUpperCase() == cleanCode,
    );

    if (existingIndex >= 0) {
      _prItems[existingIndex]['qty'] =
          (_prItems[existingIndex]['qty'] ?? 0) + qty;
    } else {
      _prItems.add({
        'item_code': cleanCode,
        'item_name': cleanCode,
        'qty': qty,
        'received_qty': 0,
        'uom': 'Unidad',
        'rate': 0,
        'purchase_order_item': '',
      });
    }

    _prQtyController.text = '1';
    _prScanController.clear();
    setState(() {});

    _prLockTimer?.cancel();
    _prLockTimer = Timer(const Duration(seconds: 2), () {
      _prScanLocked = false;
      _prLastScannedCode = '';
      if (_prScannerActive && mounted) {
        _prCameraController?.start();
      }
    });
  }

  /// Guarda el Purchase Receipt como borrador.
  Future<void> _savePR() async {
    if (_prItems.isEmpty) {
      setState(() => _prError = 'No hay items para recibir');
      return;
    }

    final provider = context.read<PurchaseOrderProvider>();
    final order = provider.currentOrder;
    if (order?.id == null) return;

    setState(() {
      _prLoading = true;
      _prError = '';
    });

    try {
      final service = context.read<ErpNextService>();
      Map<String, dynamic> result;

      if (_prSaved && _prSavedName.isNotEmpty) {
        // Ya existe un borrador — actualizar
        result = await service.updatePurchaseReceipt(
          name: _prSavedName,
          items: _prItems,
        );
      } else {
        // Crear nuevo borrador
        result = await service.createPurchaseReceipt(
          purchaseOrder: order!.id!,
          supplier: order.supplierId.isNotEmpty ? order.supplierId : order.supplier,
          warehouse: _prWarehouse.isNotEmpty ? _prWarehouse : order.setWarehouse,
          items: _prItems,
          namingSeries: _prNamingSeries,
          costCenter: order.costCenter,
        );
      }

      _prSavedName = result['name'] ?? _prSavedName;
      _prSaved = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('💾 Borrador guardado: $_prSavedName'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      _prError = 'Error guardando: $e';
    }

    setState(() => _prLoading = false);
  }

  /// Envía el Purchase Receipt y muestra el resultado.
  Future<void> _submitPR() async {
    if (!_prSaved || _prSavedName.isEmpty) {
      setState(() => _prError = 'Primero guardá el borrador');
      return;
    }

    // Confirmar antes de enviar
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar Recepción'),
        content: Text('¿Confirmás enviar $_prSavedName? No podrá modificarse después.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _prLoading = true;
      _prError = '';
    });

    try {
      final service = context.read<ErpNextService>();
      await service.submitPurchaseReceipt(_prSavedName);

      if (mounted) {
        // Mostrar diálogo de éxito con opción de ver el registro
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            title: const Text('Recepción Enviada'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_prSavedName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La recepción de mercadería fue creada exitosamente en ERPNext.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Cerrar formulario PR y volver a la PO
                  setState(() {
                    _showPRForm = false;
                    _prSaved = false;
                    _prSavedName = '';
                  });
                },
                child: const Text('Volver a PO'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  final savedPrName = _prSavedName;
                  // Cerrar formulario PR y volver a la PO
                  setState(() {
                    _showPRForm = false;
                    _prSaved = false;
                    _prSavedName = '';
                  });
                  // Navegar al detalle de la PR creada
                  final service = context.read<ErpNextService>();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PurchaseReceiptDetailScreen(
                        prName: savedPrName,
                        erpNextService: service,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Ver Registro'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _prError = 'Error enviando: $e';
    }

    setState(() => _prLoading = false);
  }

  /// Cierra el formulario de PR.
  void _closePRForm() {
    _prCameraController?.stop();
    setState(() {
      _showPRForm = false;
      _prScannerActive = false;
      _prItems = [];
      _prError = '';
      _prSaved = false;
      _prSavedName = '';
    });
  }

  // ══════════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseOrderProvider>();
    final order = provider.currentOrder;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          order?.id != null ? '📦 ${order!.id}' : '🛒 Nueva Orden',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (provider.isSubmitted)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 4),
                  Text(
                    'Enviada',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
          if (order?.id != null && !provider.isSubmitted)
            IconButton(
              onPressed: () => provider.refreshOrder(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refrescar',
            ),
        ],
      ),
      body: _showForm && order == null
          ? _buildCreationForm()
          : _buildOrderDetail(),
    );
  }

  /// Formulario de creación de orden.
  Widget _buildCreationForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.shopping_cart_checkout,
            size: 48,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 8),
          Text(
            'Crear Orden de Compra',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // ─── Serie de Numeración (PRIMER CAMPO) ───
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final series = poProvider.namingSeriesOptions;
              final loaded = poProvider.catalogsLoaded;
              if (!loaded) {
                return DropdownButtonFormField<String>(
                  isExpanded: true,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Serie de Numeración *',
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  hint: const Text(
                    'Cargando...',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                    maxLines: 1,
                  ),
                  items: const [],
                  onChanged: null,
                );
              }
              if (series.isEmpty) {
                return const InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Serie de Numeración *',
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                    isDense: true,
                    helperText: 'No hay series disponibles en ERPNext',
                  ),
                );
              }
              return DropdownButtonFormField<String>(
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Serie de Numeración *',
                  prefixIcon: Icon(Icons.tag),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                value: (series.contains(_selectedNamingSeries))
                    ? _selectedNamingSeries
                    : series.first,
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                items: series.map<DropdownMenuItem<String>>((s) {
                  return DropdownMenuItem(
                    value: s,
                    child: Text(
                      s,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedNamingSeries = val ?? '');
                },
              );
            },
          ),
          const SizedBox(height: 10),

          // Proveedor
          TextField(
            controller: _supplierController,
            decoration: const InputDecoration(
              labelText: 'Proveedor *',
              hintText: 'Escribí el nombre del proveedor',
              prefixIcon: Icon(Icons.business),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: _searchSuppliers,
          ),
          if (_supplierSuggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _supplierSuggestions.length,
                itemBuilder: (context, index) {
                  final s = _supplierSuggestions[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      s['supplier_name'] ?? s['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      s['name'] ?? '',
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      _supplierController.text =
                          s['supplier_name'] ?? s['name'] ?? '';
                      _selectedSupplierId = s['name'] ?? '';
                      setState(() => _supplierSuggestions = []);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 10),

          // Fecha
          InkWell(
            onTap: _selectDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de Entrega *',
                prefixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              child: Text(
                DateFormat('dd/MM/yyyy').format(_selectedDate),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ─── Almacén Destino ───
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final warehouses = poProvider.warehouses;
              final loaded = poProvider.catalogsLoaded;
              return DropdownButtonFormField<String>(
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Almacén Destino *',
                  prefixIcon: Icon(Icons.warehouse),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                value: _selectedWarehouse.isNotEmpty
                    ? _selectedWarehouse
                    : null,
                hint: Text(
                  !loaded ? 'Cargando...' : 'Almacén destino',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                items: warehouses.map<DropdownMenuItem<String>>((w) {
                  final name = w['name'] ?? '';
                  final displayName = w['warehouse_name'] ?? name;
                  return DropdownMenuItem(
                    value: name,
                    child: Text(
                      displayName,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedWarehouse = val ?? '');
                },
              );
            },
          ),
          const SizedBox(height: 10),

          // ─── Centro de Costos ───
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final centers = poProvider.costCenters;
              final loaded = poProvider.catalogsLoaded;
              return DropdownButtonFormField<String>(
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Centro de Costos *',
                  prefixIcon: Icon(Icons.account_balance),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                value: _selectedCostCenter.isNotEmpty
                    ? _selectedCostCenter
                    : null,
                hint: Text(
                  !loaded ? 'Cargando...' : 'Centro de costos',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                icon: const Icon(Icons.arrow_drop_down, size: 20),
                items: centers.map<DropdownMenuItem<String>>((c) {
                  final name = c['name'] ?? '';
                  final displayName = c['cost_center_name'] ?? name;
                  return DropdownMenuItem(
                    value: name,
                    child: Text(
                      displayName,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedCostCenter = val ?? '');
                },
              );
            },
          ),
          const SizedBox(height: 16),

          // Botón crear
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _createOrder,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Crear y Escanear'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Detalle de orden con escáner.
  Widget _buildOrderDetail() {
    final provider = context.watch<PurchaseOrderProvider>();
    final order = provider.currentOrder;

    if (order == null) {
      return const Center(child: Text('Orden no disponible'));
    }

    // ─── Si se está creando una recepción, mostrar formulario PR ───
    if (_showPRForm) {
      return _buildPRForm(order);
    }

    return Column(
      children: [
        // ─── CÁMARA (solo si no fue enviada) ───
        if (_cameraActive && !provider.isSubmitted)
          SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraController != null)
                  MobileScanner(
                    controller: _cameraController!,
                    onDetect: _onBarcodeDetected,
                  ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _scanLocked ? Colors.orange : Colors.blue,
                        width: 2,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (_scanLocked ? Colors.orange : Colors.blue)
                              .withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _scanLocked
                              ? '⏳ Esperá...'
                              : '📷 Escaneá un producto',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _cameraActive = !_cameraActive;
                        if (_cameraActive) {
                          _cameraController?.start();
                        } else {
                          _cameraController?.stop();
                        }
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _cameraActive ? Icons.videocam : Icons.videocam_off,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ─── CONTROLES (solo si no fue enviada) ───
        if (!provider.isSubmitted)
          Container(
            color: Colors.blue[50],
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 70,
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cant.',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _scanController,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Código',
                          hintText: 'Escanear o escribir...',
                          prefixIcon: Icon(Icons.qr_code_scanner, size: 18),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 8,
                          ),
                        ),
                        onSubmitted: (v) {
                          if (v.trim().isNotEmpty) _processScan(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () {
                        setState(() => _cameraActive = !_cameraActive);
                        if (_cameraActive) {
                          _cameraController?.start();
                        } else {
                          _cameraController?.stop();
                        }
                      },
                      icon: Icon(
                        _cameraActive ? Icons.camera_alt : Icons.keyboard,
                      ),
                      tooltip: _cameraActive ? 'Modo texto' : 'Modo cámara',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.all(6),
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                  ],
                ),

                // Último escaneo
                if (provider.lastScannedCode.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: provider.lastScanWasError
                          ? Colors.red[50]
                          : Colors.green[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      provider.lastScanMessage,
                      style: TextStyle(
                        color: provider.lastScanWasError
                            ? Colors.red[800]
                            : Colors.green[800],
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),

        // ─── INFO ORDEN ───
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.grey[100],
          child: Row(
            children: [
              Icon(Icons.business, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                order.supplier,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('dd/MM/yyyy').format(order.scheduleDate),
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${order.items.length} items — ${order.totalQty} uds',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ─── LISTA DE ITEMS ───
        Expanded(
          child: order.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 48,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Escaneá productos para agregar',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: order.items.length,
                  itemBuilder: (context, index) {
                    return _buildItemCard(order.items[index], index);
                  },
                ),
        ),

        // ─── BOTÓN ENVIAR / GUARDAR ───
        if (order.items.isNotEmpty && !provider.isSubmitted)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  // Botón Guardar (borrador)
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: provider.isLoading ? null : _saveOrder,
                        icon: provider.isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          provider.isSaved ? 'Actualizar' : 'Guardar',
                          style: const TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botón Enviar (submit)
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: (provider.isLoading || !provider.isSaved)
                            ? null
                            : _submitOrder,
                        icon: const Icon(Icons.send),
                        label: const Text(
                          'Enviar',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: provider.isSaved
                              ? Colors.green
                              : Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ─── BOTÓN CREAR RECEPCIÓN (solo si la PO fue enviada) ───
        if (provider.isSubmitted)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _prLoading ? null : _openPRForm,
                  icon: _prLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.local_shipping),
                  label: const Text(
                    'Crear Recepción de Mercadería',
                    style: TextStyle(fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Formulario inline de creación de Purchase Receipt.
  Widget _buildPRForm(PurchaseOrder order) {
    return Column(
      children: [
        // ─── HEADER ───
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _prSaved ? Colors.green[50] : Colors.teal[50],
          child: Row(
            children: [
              Icon(
                _prSaved ? Icons.check_circle : Icons.local_shipping,
                size: 18,
                color: _prSaved ? Colors.green[700] : Colors.teal[700],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _prSaved ? 'Borrador Guardado' : 'Nueva Recepción de Mercadería',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _prSaved ? Colors.green[800] : Colors.teal[800],
                      ),
                    ),
                    if (_prSaved && _prSavedName.isNotEmpty)
                      Text(
                        _prSavedName,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _closePRForm,
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Cerrar',
              ),
            ],
          ),
        ),

        // ─── SCANNER (solo si se activó) ───
        if (_prScannerActive)
          SizedBox(
            height: 150,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_prCameraController != null)
                  MobileScanner(
                    controller: _prCameraController!,
                    onDetect: _onPRBarcodeDetected,
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _prScannerActive = false;
                        _prCameraController?.stop();
                      });
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _prScanLocked ? '⏳ Esperá...' : '📷 Escaneá producto',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ─── CONTROLES ───
        Container(
          color: Colors.teal[50],
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // Toggle cámara
              IconButton(
                onPressed: () {
                  setState(() {
                    _prScannerActive = !_prScannerActive;
                    if (_prScannerActive) {
                      _prCameraController = MobileScannerController(
                        detectionSpeed: DetectionSpeed.noDuplicates,
                        facing: CameraFacing.back,
                        torchEnabled: false,
                      );
                    } else {
                      _prCameraController?.stop();
                      _prCameraController?.dispose();
                      _prCameraController = null;
                    }
                  });
                },
                icon: Icon(_prScannerActive ? Icons.camera_alt : Icons.qr_code_scanner),
                tooltip: _prScannerActive ? 'Cerrar escáner' : 'Abrir escáner',
                style: IconButton.styleFrom(
                  backgroundColor: _prScannerActive ? Colors.orange : Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              // Cantidad
              SizedBox(
                width: 55,
                child: TextField(
                  controller: _prQtyController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    labelText: 'Cant.',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Código manual
              Expanded(
                child: TextField(
                  controller: _prScanController,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Código manual',
                    hintText: 'Escribir código...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _processPRScan(v);
                  },
                ),
              ),
            ],
          ),
        ),

        // ─── INFORMACIÓN ───
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.grey[100],
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'PO: ${order.id ?? ""} — ${order.supplier}',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              const Spacer(),
              Text(
                '${_prItems.length} items',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal[700]),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ─── LISTA DE ITEMS ───
        Expanded(
          child: _prItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text('No hay items', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemCount: _prItems.length,
                  itemBuilder: (context, index) {
                    final item = _prItems[index];
                    final pending = (item['qty'] ?? 0) - (item['received_qty'] ?? 0);
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['item_name'] ?? item['item_code'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${item["item_code"]} — Pedido: ${item["qty"]} — Pendiente: $pending',
                                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  onPressed: () {
                                    final newQty = (_prItems[index]['qty'] ?? 0) - 1;
                                    if (newQty <= 0) {
                                      setState(() => _prItems.removeAt(index));
                                    } else {
                                      setState(() => _prItems[index]['qty'] = newQty);
                                    }
                                  },
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  color: Colors.red,
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                                Container(
                                  width: 36,
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${_prItems[index]["qty"]}',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() => _prItems[index]['qty'] = (_prItems[index]['qty'] ?? 0) + 1);
                                  },
                                  icon: const Icon(Icons.add_circle_outline, size: 20),
                                  color: Colors.green,
                                  padding: const EdgeInsets.all(2),
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),

        // ─── ERROR ───
        if (_prError.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.red[50],
            child: Text(
              _prError,
              style: TextStyle(color: Colors.red[700], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),

        // ─── BOTONES GUARDAR / ENVIAR ───
        SafeArea(
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _prLoading || _prItems.isEmpty ? null : _savePR,
                      icon: _prLoading
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save),
                      label: Text(_prSaved ? 'Actualizar' : 'Guardar', style: const TextStyle(fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _prLoading || !_prSaved ? null : _submitPR,
                      icon: const Icon(Icons.send),
                      label: const Text('Enviar', style: TextStyle(fontSize: 14)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _prSaved ? Colors.green : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(PurchaseOrderItem item, int index) {
    final provider = context.read<PurchaseOrderProvider>();
    final readOnly = provider.isSubmitted;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      color: readOnly ? Colors.grey[50] : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.itemName.isNotEmpty ? item.itemName : item.itemCode,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: readOnly ? Colors.grey[600] : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.itemCode,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                ],
              ),
            ),
            if (readOnly)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '${item.qty}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () =>
                        provider.updateItemQty(index, item.qty - 1),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: Colors.red,
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  Container(
                    width: 36,
                    alignment: Alignment.center,
                    child: Text(
                      '${item.qty}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        provider.updateItemQty(index, item.qty + 1),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                    color: Colors.green,
                    padding: const EdgeInsets.all(2),
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
