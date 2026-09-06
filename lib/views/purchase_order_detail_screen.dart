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
import '../theme/app_design.dart';
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

  // ─── Recepciones vinculadas a la PO ───
  List<Map<String, dynamic>> _linkedPRs = [];
  bool _linkedPRsLoading = false;
  bool _linkedPRsLoaded = false;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
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
        SnackBar(
          content: const Text('⚠️ Seleccioná un proveedor'),
          backgroundColor: AppDesign.orangeIcon,
        ),
      );
      return;
    }

    if (_selectedWarehouse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ Seleccioná un almacén destino'),
          backgroundColor: AppDesign.orangeIcon,
        ),
      );
      return;
    }

    if (_selectedCostCenter.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ Seleccioná un centro de costos'),
          backgroundColor: AppDesign.orangeIcon,
        ),
      );
      return;
    }

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
          backgroundColor: AppDesign.blueIcon,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${provider.error}'),
          backgroundColor: AppDesign.statusCancelled,
        ),
      );
    }
  }

  Future<void> _submitOrder() async {
    final provider = context.read<PurchaseOrderProvider>();

    if (!provider.isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ Primero guardá la orden como borrador'),
          backgroundColor: AppDesign.orangeIcon,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
            child: const Text('Enviar', style: TextStyle(color: AppDesign.statusSubmitted)),
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
          backgroundColor: AppDesign.statusSubmitted,
        ),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${provider.error}'),
          backgroundColor: AppDesign.statusCancelled,
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // PURCHASE RECEIPT (recepción desde PO)
  // ══════════════════════════════════════════════════════════════

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

      final results = await Future.wait([
        service.getPurchaseOrderDetail(order.id!),
        service.fetchPurchaseReceiptNamingSeries(),
      ]);

      final poDetail = results[0] as Map<String, dynamic>?;
      final series = results[1] as List<String>;

      if (poDetail != null && poDetail['items'] != null) {
        final items = List<Map<String, dynamic>>.from(poDetail['items']);
        _prItems = items
            .map(
              (item) => {
                'item_code': item['item_code'] ?? '',
                'item_name': item['item_name'] ?? '',
                'qty': item['qty'] ?? 0,
                'received_qty': item['received_qty'] ?? 0,
                'uom': item['uom'] ?? 'Unidad',
                'rate': item['rate'] ?? 0,
                'purchase_order_item': item['name'] ?? '',
              },
            )
            .toList();
      }

      _prNamingSeriesOptions = series;
      if (series.isNotEmpty) _prNamingSeries = series.first;
    } catch (e) {
      _prError = 'Error cargando datos: $e';
    }

    setState(() => _prLoading = false);

    _loadLinkedPRs();
  }

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
        result = await service.updatePurchaseReceipt(
          name: _prSavedName,
          items: _prItems,
        );
      } else {
        result = await service.createPurchaseReceipt(
          purchaseOrder: order!.id!,
          supplier: order.supplierId.isNotEmpty
              ? order.supplierId
              : order.supplier,
          warehouse: _prWarehouse.isNotEmpty
              ? _prWarehouse
              : order.setWarehouse,
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
            backgroundColor: AppDesign.blueIcon,
          ),
        );
      }
    } catch (e) {
      _prError = 'Error guardando: $e';
    }

    setState(() => _prLoading = false);
  }

  Future<void> _submitPR() async {
    if (!_prSaved || _prSavedName.isEmpty) {
      setState(() => _prError = 'Primero guardá el borrador');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enviar Recepción'),
        content: Text(
          '¿Confirmás enviar $_prSavedName? No podrá modificarse después.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar', style: TextStyle(color: AppDesign.statusSubmitted)),
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
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            icon: const Icon(Icons.check_circle, color: AppDesign.statusSubmitted, size: 48),
            title: const Text('Recepción Enviada'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _prSavedName,
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
                  setState(() {
                    _showPRForm = false;
                    _prSaved = false;
                    _prSavedName = '';
                  });
                  _linkedPRsLoaded = false;
                  _loadLinkedPRs();
                },
                child: const Text('Volver a PO'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  final savedPrName = _prSavedName;
                  setState(() {
                    _showPRForm = false;
                    _prSaved = false;
                    _prSavedName = '';
                  });
                  _linkedPRsLoaded = false;
                  _loadLinkedPRs();
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
                  backgroundColor: AppDesign.tealIcon,
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

  void _closePRForm() {
    _prCameraController?.stop();
    setState(() {
      _showPRForm = false;
      _prScannerActive = false;
      _prItems = [];
      _prError = '';
      _prSaved = false;
      _prSavedName = '';
      _linkedPRsLoaded = false;
    });
  }

  Future<void> _loadLinkedPRs() async {
    final provider = context.read<PurchaseOrderProvider>();
    final order = provider.currentOrder;
    if (order == null || order.id == null) return;

    setState(() => _linkedPRsLoading = true);
    try {
      final service = context.read<ErpNextService>();
      final prs = await service.listPurchaseReceiptsForPO(order.id!);
      setState(() {
        _linkedPRs = prs;
        _linkedPRsLoaded = true;
      });
    } catch (e) {
      print('[PR] Error loading linked PRs: $e');
      setState(() => _linkedPRsLoaded = true);
    }
    setState(() => _linkedPRsLoading = false);
  }

  // ══════════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseOrderProvider>();
    final order = provider.currentOrder;

    return Scaffold(
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── HEADER NAVY ───
          AppDesign.buildHeader(
            title: order?.id != null ? '📦 ${order!.id}' : '🛒 Nueva Orden',
            icon: order?.id != null ? Icons.receipt_long : Icons.shopping_cart,
            subtitle: order?.id != null
                ? (provider.isSubmitted ? 'Orden enviada' : 'Editando borrador')
                : 'Crear nueva orden de compra',
            showBack: true,
            onBack: () => Navigator.pop(context),
            actions: [
              if (provider.isSubmitted)
                AppDesign.statusBadge('Enviada', AppDesign.statusSubmitted),
              if (order?.id != null && !provider.isSubmitted)
                GestureDetector(
                  onTap: () => provider.refreshOrder(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.refresh, color: Colors.white, size: 18),
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),
          // ─── BODY ───
          Expanded(
            child: _showForm && order == null
                ? _buildCreationForm()
                : _buildOrderDetail(),
          ),
        ],
      ),
    );
  }

  /// Formulario de creación de orden — estilo AppDesign.
  Widget _buildCreationForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Card central con ícono ───
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppDesign.cardWhite,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.navy.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                AppDesign.circleAvatar(
                  icon: Icons.shopping_cart_checkout,
                  bgColor: AppDesign.orangeLight,
                  iconColor: AppDesign.orangeIcon,
                  size: 56,
                ),
                const SizedBox(height: 12),
                Text(
                  'Crear Orden de Compra',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppDesign.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Completá los datos para generar la orden',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── Serie de Numeración ───
          _buildSectionLabel('SERIE DE NUMERACIÓN'),
          const SizedBox(height: 6),
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final series = poProvider.namingSeriesOptions;
              final loaded = poProvider.catalogsLoaded;
              if (!loaded) {
                return _buildDropdownField(
                  label: 'Serie de Numeración *',
                  icon: Icons.tag,
                  hint: 'Cargando...',
                  items: const [],
                  value: null,
                  enabled: false,
                );
              }
              if (series.isEmpty) {
                return _buildDropdownField(
                  label: 'Serie de Numeración *',
                  icon: Icons.tag,
                  hint: 'No hay series disponibles',
                  items: const [],
                  value: null,
                  enabled: false,
                );
              }
              final currentVal = (series.contains(_selectedNamingSeries))
                  ? _selectedNamingSeries
                  : series.first;
              return _buildDropdownField(
                label: 'Serie de Numeración *',
                icon: Icons.tag,
                hint: 'Seleccionar serie',
                items: series.map((s) => DropdownMenuItem(value: s, child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                value: currentVal,
                onChanged: (val) => setState(() => _selectedNamingSeries = val ?? ''),
              );
            },
          ),

          const SizedBox(height: 16),

          // ─── Proveedor ───
          _buildSectionLabel('PROVEEDOR'),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppDesign.cardWhite,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.navy.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: _supplierController,
                  decoration: InputDecoration(
                    labelText: 'Proveedor *',
                    hintText: 'Escribí el nombre del proveedor',
                    prefixIcon: const Icon(Icons.business, color: AppDesign.navy),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppDesign.cardWhite,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  onChanged: _searchSuppliers,
                ),
                if (_supplierSuggestions.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _supplierSuggestions.length,
                      itemBuilder: (context, index) {
                        final s = _supplierSuggestions[index];
                        return ListTile(
                          dense: true,
                          leading: AppDesign.circleAvatar(
                            icon: Icons.business,
                            bgColor: AppDesign.blueLight,
                            iconColor: AppDesign.blueIcon,
                            size: 32,
                          ),
                          title: Text(
                            s['supplier_name'] ?? s['name'] ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            s['name'] ?? '',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ─── Fecha de Entrega ───
          _buildSectionLabel('FECHA DE ENTREGA'),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppDesign.cardWhite,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.navy.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Fecha de Entrega *',
                  prefixIcon: const Icon(Icons.calendar_today, color: AppDesign.navy),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppDesign.cardWhite,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                child: Text(
                  DateFormat('dd/MM/yyyy').format(_selectedDate),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Almacén Destino ───
          _buildSectionLabel('ALMACÉN DESTINO'),
          const SizedBox(height: 6),
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final warehouses = poProvider.warehouses;
              final loaded = poProvider.catalogsLoaded;
              return _buildDropdownField(
                label: 'Almacén Destino *',
                icon: Icons.warehouse,
                hint: !loaded ? 'Cargando...' : 'Seleccionar almacén',
                items: warehouses.map<DropdownMenuItem<String>>((w) {
                  final name = (w['name'] ?? '').toString();
                  final displayName = (w['warehouse_name'] ?? name).toString();
                  return DropdownMenuItem<String>(value: name, child: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis));
                }).toList(),
                value: _selectedWarehouse.isNotEmpty ? _selectedWarehouse : null,
                onChanged: (val) => setState(() => _selectedWarehouse = val ?? ''),
              );
            },
          ),

          const SizedBox(height: 16),

          // ─── Centro de Costos ───
          _buildSectionLabel('CENTRO DE COSTOS'),
          const SizedBox(height: 6),
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final centers = poProvider.costCenters;
              final loaded = poProvider.catalogsLoaded;
              return _buildDropdownField(
                label: 'Centro de Costos *',
                icon: Icons.account_balance,
                hint: !loaded ? 'Cargando...' : 'Seleccionar centro',
                items: centers.map<DropdownMenuItem<String>>((c) {
                  final name = (c['name'] ?? '').toString();
                  final displayName = (c['cost_center_name'] ?? name).toString();
                  return DropdownMenuItem<String>(value: name, child: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis));
                }).toList(),
                value: _selectedCostCenter.isNotEmpty ? _selectedCostCenter : null,
                onChanged: (val) => setState(() => _selectedCostCenter = val ?? ''),
              );
            },
          ),

          const SizedBox(height: 24),

          // ─── Botón Crear ───
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _createOrder,
              icon: const Icon(Icons.arrow_forward, size: 20),
              label: const Text(
                'Crear y Escanear',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesign.navy,
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: AppDesign.navy.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper — label de sección estilo dashboard.
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Colors.grey[500],
        letterSpacing: 0.8,
      ),
    );
  }

  /// Helper — dropdown field estilo AppDesign.
  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required String? value,
    ValueChanged<String?>? onChanged,
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppDesign.cardWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppDesign.navy.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppDesign.navy),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: enabled ? AppDesign.cardWhite : Colors.grey[100],
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        initialValue: value,
        hint: Text(
          hint,
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        icon: Icon(Icons.arrow_drop_down, size: 22, color: enabled ? AppDesign.navy : Colors.grey),
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  /// Detalle de orden con escáner — estilo AppDesign.
  Widget _buildOrderDetail() {
    final provider = context.watch<PurchaseOrderProvider>();
    final order = provider.currentOrder;

    if (order == null) {
      return AppDesign.emptyState(
        icon: Icons.receipt_long,
        title: 'Orden no disponible',
      );
    }

    if (provider.isSubmitted && !_linkedPRsLoaded && !_linkedPRsLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLinkedPRs());
    }

    if (_showPRForm) {
      return _buildPRForm(order);
    }

    return Column(
      children: [
        // ─── CÁMARA ───
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
                        color: _scanLocked ? AppDesign.orangeIcon : AppDesign.accent,
                        width: 2.5,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: (_scanLocked ? AppDesign.orangeIcon : AppDesign.accent).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _scanLocked ? '⏳ Esperá...' : '📷 Escaneá un producto',
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
                      decoration: BoxDecoration(
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

        // ─── CONTROLES ───
        if (!provider.isSubmitted)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppDesign.cardWhite,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.navy.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Cantidad
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Cant.',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          filled: true,
                          fillColor: AppDesign.bg,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Código
                    Expanded(
                      child: TextField(
                        controller: _scanController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Código',
                          hintText: 'Escanear o escribir...',
                          prefixIcon: Icon(Icons.qr_code_scanner, size: 18, color: AppDesign.accent),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                          filled: true,
                          fillColor: AppDesign.bg,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        ),
                        onSubmitted: (v) {
                          if (v.trim().isNotEmpty) _processScan(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Toggle cámara
                    GestureDetector(
                      onTap: () {
                        setState(() => _cameraActive = !_cameraActive);
                        if (_cameraActive) {
                          _cameraController?.start();
                        } else {
                          _cameraController?.stop();
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppDesign.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _cameraActive ? Icons.camera_alt : Icons.keyboard,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),

                // Último escaneo
                if (provider.lastScannedCode.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: provider.lastScanWasError
                          ? AppDesign.statusCancelled.withValues(alpha: 0.08)
                          : AppDesign.statusSubmitted.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      provider.lastScanMessage,
                      style: TextStyle(
                        color: provider.lastScanWasError
                            ? AppDesign.statusCancelled
                            : AppDesign.statusSubmitted,
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
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppDesign.cardWhite,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppDesign.navy.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              AppDesign.circleAvatar(
                icon: Icons.business,
                bgColor: AppDesign.blueLight,
                iconColor: AppDesign.blueIcon,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.supplier,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppDesign.navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat('dd/MM/yyyy').format(order.scheduleDate),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppDesign.orangeLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${order.items.length} items · ${order.totalQty} uds',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppDesign.orangeIcon,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ─── LISTA DE ITEMS ───
        Expanded(
          child: order.items.isEmpty
              ? AppDesign.emptyState(
                  icon: Icons.qr_code_scanner,
                  title: 'Escaneá productos para agregar',
                  subtitle: 'Usá la cámara o escribí el código',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  itemCount: order.items.length,
                  itemBuilder: (context, index) {
                    return _buildItemCard(order.items[index], index);
                  },
                ),
        ),

        // ─── BOTONES GUARDAR / ENVIAR ───
        if (order.items.isNotEmpty && !provider.isSubmitted)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
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
                            : const Icon(Icons.save, size: 18),
                        label: Text(
                          provider.isSaved ? 'Actualizar' : 'Guardar',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppDesign.blueIcon,
                          foregroundColor: Colors.white,
                          elevation: 3,
                          shadowColor: AppDesign.blueIcon.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: (provider.isLoading || !provider.isSaved)
                            ? null
                            : _submitOrder,
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text(
                          'Enviar',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: provider.isSaved
                              ? AppDesign.statusSubmitted
                              : Colors.grey[400],
                          foregroundColor: Colors.white,
                          elevation: provider.isSaved ? 3 : 0,
                          shadowColor: AppDesign.statusSubmitted.withValues(alpha: 0.4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ─── RECEPCIONES VINCULADAS ───
        if (provider.isSubmitted && !_showPRForm)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppDesign.cardWhite,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.tealIcon.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppDesign.circleAvatar(
                      icon: Icons.receipt_long,
                      bgColor: AppDesign.tealLight,
                      iconColor: AppDesign.tealIcon,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Recepciones de Mercadería',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppDesign.navy,
                      ),
                    ),
                    const Spacer(),
                    if (_linkedPRsLoading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppDesign.accent),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_linkedPRs.isEmpty && !_linkedPRsLoading)
                  Text(
                    'No hay recepciones vinculadas',
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                if (_linkedPRs.isNotEmpty)
                  ..._linkedPRs.map((pr) {
                    final docstatus = pr['docstatus'] ?? 0;
                    final isDraft = docstatus == 0;
                    final isSubmitted = docstatus == 1;
                    final statusColor = isSubmitted
                        ? AppDesign.statusSubmitted
                        : isDraft
                        ? AppDesign.statusDraft
                        : AppDesign.statusCancelled;
                    final statusText = isSubmitted
                        ? 'Enviado'
                        : isDraft
                        ? 'Borrador'
                        : 'Cancelado';
                    return GestureDetector(
                      onTap: () {
                        final service = context.read<ErpNextService>();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PurchaseReceiptDetailScreen(
                              prName: pr['name'],
                              erpNextService: service,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isDraft ? Icons.edit_note : Icons.check_circle,
                              color: statusColor,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pr['name'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppDesign.navy,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${pr['posting_date'] ?? ''} — Bs. ${pr['grand_total'] ?? 0}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ),
                            AppDesign.statusBadge(statusText, statusColor),
                            const SizedBox(width: 6),
                            Icon(Icons.chevron_right, color: Colors.grey[400], size: 18),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),

        // ─── BOTÓN CREAR RECEPCIÓN ───
        if (provider.isSubmitted)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: SizedBox(
                height: 52,
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
                      : const Icon(Icons.local_shipping, size: 20),
                  label: const Text(
                    'Crear Recepción de Mercadería',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppDesign.tealIcon,
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: AppDesign.tealIcon.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Formulario inline de creación de Purchase Receipt — estilo AppDesign.
  Widget _buildPRForm(PurchaseOrder order) {
    return Column(
      children: [
        // ─── HEADER PR ───
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: _prSaved
              ? AppDesign.statusSubmitted.withValues(alpha: 0.08)
              : AppDesign.tealLight,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (_prSaved ? AppDesign.statusSubmitted : AppDesign.tealIcon).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _prSaved ? Icons.check_circle : Icons.local_shipping,
                  size: 16,
                  color: _prSaved ? AppDesign.statusSubmitted : AppDesign.tealIcon,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _prSaved ? 'Borrador Guardado' : 'Nueva Recepción de Mercadería',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _prSaved ? AppDesign.statusSubmitted : AppDesign.tealIcon,
                      ),
                    ),
                    if (_prSaved && _prSavedName.isNotEmpty)
                      Text(
                        _prSavedName,
                        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
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

        // ─── SCANNER ───
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppDesign.tealIcon.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _prScanLocked ? '⏳ Esperá...' : '📷 Escaneá producto',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ─── CONTROLES PR ───
        Container(
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppDesign.cardWhite,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppDesign.navy.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
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
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _prScannerActive ? AppDesign.orangeIcon : AppDesign.tealIcon,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _prScannerActive ? Icons.camera_alt : Icons.qr_code_scanner,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 55,
                child: TextField(
                  controller: _prQtyController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Cant.',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    filled: true,
                    fillColor: AppDesign.bg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _prScanController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Código manual',
                    hintText: 'Escribir código...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[200]!),
                    ),
                    filled: true,
                    fillColor: AppDesign.bg,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _processPRScan(v);
                  },
                ),
              ),
            ],
          ),
        ),

        // ─── INFO PR ───
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppDesign.cardWhite,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                'PO: ${order.id ?? ""} — ${order.supplier}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppDesign.tealLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_prItems.length} items',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppDesign.tealIcon,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ─── LISTA DE ITEMS PR ───
        Expanded(
          child: _prItems.isEmpty
              ? AppDesign.emptyState(
                  icon: Icons.inbox_outlined,
                  title: 'No hay items',
                  subtitle: 'Escaneá o escribí códigos para recibir',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _prItems.length,
                  itemBuilder: (context, index) {
                    final item = _prItems[index];
                    final pending =
                        (item['qty'] ?? 0) - (item['received_qty'] ?? 0);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppDesign.cardWhite,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppDesign.navy.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          AppDesign.circleAvatar(
                            icon: Icons.inventory_2,
                            bgColor: AppDesign.tealLight,
                            iconColor: AppDesign.tealIcon,
                            size: 32,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (item['item_name'] ?? item['item_code'] ?? '').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppDesign.navy,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${item["item_code"]} — Ped: ${item["qty"]} — Pend: $pending',
                                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  final newQty = (_prItems[index]['qty'] ?? 0) - 1;
                                  if (newQty <= 0) {
                                    setState(() => _prItems.removeAt(index));
                                  } else {
                                    setState(() => _prItems[index]['qty'] = newQty);
                                  }
                                },
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppDesign.statusCancelled.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.remove, size: 16, color: AppDesign.statusCancelled),
                                ),
                              ),
                              Container(
                                width: 36,
                                alignment: Alignment.center,
                                child: Text(
                                  '${_prItems[index]["qty"]}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppDesign.navy,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setState(
                                    () => _prItems[index]['qty'] = (_prItems[index]['qty'] ?? 0) + 1,
                                  );
                                },
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppDesign.statusSubmitted.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, size: 16, color: AppDesign.statusSubmitted),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // ─── ERROR ───
        if (_prError.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppDesign.statusCancelled.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _prError,
              style: const TextStyle(color: AppDesign.statusCancelled, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),

        // ─── BOTONES GUARDAR / ENVIAR PR ───
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _prLoading || _prItems.isEmpty ? null : _savePR,
                      icon: _prLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save, size: 18),
                      label: Text(
                        _prSaved ? 'Actualizar' : 'Guardar',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppDesign.blueIcon,
                        foregroundColor: Colors.white,
                        elevation: 3,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text(
                        'Enviar',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _prSaved ? AppDesign.statusSubmitted : Colors.grey[400],
                        foregroundColor: Colors.white,
                        elevation: _prSaved ? 3 : 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    return AppDesign.buildListCard(
      context: context,
      accentColor: readOnly ? Colors.grey : AppDesign.accent,
      child: Row(
        children: [
          AppDesign.circleAvatar(
            icon: Icons.inventory_2,
            bgColor: readOnly ? Colors.grey[100]! : AppDesign.orangeLight,
            iconColor: readOnly ? Colors.grey[500]! : AppDesign.orangeIcon,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName.isNotEmpty ? item.itemName : item.itemCode,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: readOnly ? Colors.grey[500] : AppDesign.navy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.itemCode,
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ],
            ),
          ),
          if (readOnly)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppDesign.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${item.qty}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppDesign.navy,
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => provider.updateItemQty(index, item.qty - 1),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppDesign.statusCancelled.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.remove, size: 16, color: AppDesign.statusCancelled),
                  ),
                ),
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Text(
                    '${item.qty}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppDesign.navy,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => provider.updateItemQty(index, item.qty + 1),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppDesign.statusSubmitted.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add, size: 16, color: AppDesign.statusSubmitted),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
