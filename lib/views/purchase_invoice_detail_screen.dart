import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_invoice_provider.dart';
import '../models/purchase_invoice.dart';
import '../theme/app_design.dart';
import 'ui_helpers.dart';

/// Pantalla de creación y detalle de Factura de Compra (Purchase Invoice).
/// Copia la lógica de la Recepción de Mercadería: escáner en modo pila LIFO,
/// búsqueda escrita y cantidades con decimales según la UOM del producto.
///
/// El tilde "Actualizar inventario" (update_stock) se marca según el origen:
/// - Orden de Compra → Factura directa: ✅ (la factura mueve el stock)
/// - Creación directa: ✅
/// - Desde la Recepción: ❌ (el stock ya lo actualizó la recepción)
class PurchaseInvoiceDetailScreen extends StatefulWidget {
  const PurchaseInvoiceDetailScreen({super.key});

  @override
  State<PurchaseInvoiceDetailScreen> createState() =>
      _PurchaseInvoiceDetailScreenState();
}

class _PurchaseInvoiceDetailScreenState
    extends State<PurchaseInvoiceDetailScreen> {
  // ─── Cámara ───
  MobileScannerController? _cameraController;
  bool _cameraActive = true;
  bool _scanLocked = false;
  String _lastScannedCode = '';
  Timer? _lockTimer;
  // ─── Pila de escaneos: se procesan en cola, sin perder ninguno ───
  final List<String> _scanQueue = [];
  bool _isProcessingScan = false;

  // ─── Formulario ───
  String _pendingPOName = '';
  String _pendingReceiptName = '';
  final _supplierController = TextEditingController();
  String _selectedSupplierId = '';
  final _billNoController = TextEditingController();
  final _scanController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  bool _showForm = true;

  // ─── Estado de edición de precios (para colapsar cámara) ───
  bool _priceEditing = false;

  // ─── Cache de controllers para campos de precio ───
  final Map<String, TextEditingController> _rateControllers = {};

  // ─── Campos ───
  String _selectedWarehouse = '';
  String _selectedCostCenter = '';
  String _selectedNamingSeries = '';
  DateTime _selectedDate = DateTime.now();
  bool _updateStock = true; // Se ajusta según el origen en initState
  List<Map<String, dynamic>> _supplierSuggestions = [];

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
      final piProvider = context.read<PurchaseInvoiceProvider>();
      piProvider.loadItemsCache(inventoryProvider.itemsByCode);
      piProvider.fetchCatalogs().then((_) async {
        // Si no hay serie seleccionada, usar la primera disponible
        if (mounted &&
            _selectedNamingSeries.isEmpty &&
            piProvider.namingSeriesOptions.isNotEmpty) {
          setState(
              () => _selectedNamingSeries = piProvider.namingSeriesOptions.first);
        }
        // Si la conexión terminó después de abrir esta pantalla, esperar a que
        // carguen los items del inventario y recargar el cache (al abrir podía
        // estar vacío si aún no conectaba).
        if (mounted && piProvider.itemsByCode.isEmpty) {
          for (var i = 0;
              i < 30 && inventoryProvider.itemsByCode.isEmpty;
              i++) {
            await Future.delayed(const Duration(seconds: 1));
          }
          if (mounted) piProvider.loadItemsCache(inventoryProvider.itemsByCode);
        }
      });

      // Origen: orden de compra, recepción, o creación directa
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _supplierController.text = args['supplier'] ?? '';
        _selectedSupplierId = args['supplierId'] ?? '';
        _selectedWarehouse = args['warehouse'] ?? '';
        _selectedCostCenter = args['costCenter'] ?? '';
        if (args['receiptName'] != null) {
          // Desde la recepción: el stock ya está actualizado → tilde apagado
          _pendingReceiptName = args['receiptName'];
          _updateStock = false;
        } else if (args['poName'] != null) {
          // Desde la orden directo a facturar: la factura mueve el stock
          _pendingPOName = args['poName'];
          _updateStock = true;
        }
      }
      // Creación directa → _updateStock queda en true
    });
  }

  TextEditingController _getRateController(String itemCode, double value) {
    final key = itemCode;
    if (!_rateControllers.containsKey(key)) {
      _rateControllers[key] = TextEditingController(
        text: value > 0 ? value.toStringAsFixed(2) : '',
      );
    }
    return _rateControllers[key]!;
  }

  void _cleanupRateControllers(List<PurchaseInvoiceItem> items) {
    final activeKeys = <String>{};
    for (final item in items) {
      activeKeys.add(item.itemCode);
    }
    final toRemove = _rateControllers.keys
        .where((k) => !activeKeys.contains(k))
        .toList();
    for (final k in toRemove) {
      _rateControllers[k]!.dispose();
      _rateControllers.remove(k);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _lockTimer?.cancel();
    _scanQueue.clear();
    _supplierController.dispose();
    _billNoController.dispose();
    _scanController.dispose();
    _qtyController.dispose();
    for (final c in _rateControllers.values) {
      c.dispose();
    }
    _rateControllers.clear();
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

    // Encolar el escaneo y seguir escaneando — la pila procesa sola
    _scanQueue.add(code);
    _drainScanQueue();
  }

  /// Procesa la pila de escaneos uno por uno, sin solaparse.
  Future<void> _drainScanQueue() async {
    if (_isProcessingScan) return;
    _isProcessingScan = true;
    while (_scanQueue.isNotEmpty && mounted) {
      final code = _scanQueue.removeAt(0);
      HapticFeedback.mediumImpact();
      try {
        final provider = context.read<PurchaseInvoiceProvider>();
        final qty = double.tryParse(
                _qtyController.text.trim().replaceAll(',', '.')) ??
            1.0;
        await provider.scanItemToInvoice(code, quantity: qty);
        _qtyController.text = '1';
        _scanController.clear();
      } catch (_) {}
      // Pausa mínima para que el mismo código no vuelva a entrar en cola
      // de inmediato (anti-doble-lectura), pero sin bloquear nuevos códigos
      _lastScannedCode = '';
      _scanLocked = false;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _isProcessingScan = false;
  }

  // ══════════════════════════════════════════════════════════════
  // ACCIONES
  // ══════════════════════════════════════════════════════════════

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
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
    final provider = context.read<PurchaseInvoiceProvider>();
    final results = await provider.searchSuppliers(query);
    if (mounted) {
      setState(() => _supplierSuggestions = results);
    }
  }

  void _startCreation() {
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
          content: const Text('⚠️ Seleccioná un almacén'),
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

    final provider = context.read<PurchaseInvoiceProvider>();
    final namingSeries = _selectedNamingSeries.isNotEmpty
        ? _selectedNamingSeries
        : (provider.namingSeriesOptions.isNotEmpty
            ? provider.namingSeriesOptions.first
            : '');

    if (_pendingReceiptName.isNotEmpty) {
      // Desde la recepción: items precargados de lo recibido, sin tilde stock
      provider
          .createFromReceipt(
        _pendingReceiptName,
        supplier: _supplierController.text.trim(),
        supplierId: _selectedSupplierId,
        billNo: _billNoController.text.trim(),
        namingSeries: namingSeries,
        warehouse: _selectedWarehouse,
        costCenter: _selectedCostCenter,
      )
          .then((_) {
        if (mounted) {
          setState(() => _showForm = false);
        }
      });
    } else if (_pendingPOName.isNotEmpty) {
      // Desde la orden directo a facturar: con tilde de actualizar inventario
      provider
          .createFromPO(
        _pendingPOName,
        supplier: _supplierController.text.trim(),
        supplierId: _selectedSupplierId,
        billNo: _billNoController.text.trim(),
        namingSeries: namingSeries,
        warehouse: _selectedWarehouse,
        costCenter: _selectedCostCenter,
      )
          .then((_) {
        if (mounted) {
          setState(() => _showForm = false);
        }
      });
    } else {
      // Creación directa: también con tilde de actualizar inventario
      provider.createNewInvoice(
        supplier: _supplierController.text.trim(),
        supplierId: _selectedSupplierId,
        billNo: _billNoController.text.trim(),
        namingSeries: namingSeries,
        warehouse: _selectedWarehouse,
        costCenter: _selectedCostCenter,
        updateStock: _updateStock,
        postingDate: _selectedDate,
      );
      setState(() => _showForm = false);
    }
  }

  Future<void> _saveInvoice() async {
    final provider = context.read<PurchaseInvoiceProvider>();
    // Sincronizar el Nº de factura escrito antes de guardar
    provider.updateBillNo(_billNoController.text.trim());
    final ok = await provider.saveInvoice();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💾 Borrador guardado: ${provider.currentInvoice?.id ?? ''}',
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${provider.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submitInvoice() async {
    final provider = context.read<PurchaseInvoiceProvider>();

    if (!provider.isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Primero guardá la factura como borrador'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar factura'),
        content: const Text(
          '¿Confirmás que querés enviar esta factura de compra a ERPNext? No podrá modificarse después.',
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

    final ok = await provider.submitInvoice();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Factura ${provider.currentInvoice?.id ?? ''} enviada',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
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
  // UI
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PurchaseInvoiceProvider>();
    final invoice = provider.currentInvoice;

    return Scaffold(
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── Header navy ───
          AppDesign.buildHeader(
            title: invoice?.id != null ? '🧾 ${invoice!.id}' : '🧾 Nueva Factura',
            subtitle: provider.isSubmitted
                ? 'Factura enviada a ERPNext'
                : invoice?.id != null
                    ? 'Factura en borrador'
                    : 'Crear nueva factura de compra',
            icon: Icons.receipt_long_outlined,
            onBack: () => Navigator.pop(context),
            actions: [
              if (provider.isSubmitted)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppDesign.statusSubmitted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 13, color: AppDesign.statusSubmitted),
                      const SizedBox(width: 4),
                      Text(
                        'Enviada',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppDesign.statusSubmitted,
                        ),
                      ),
                    ],
                  ),
                ),
              if (invoice?.id != null && !provider.isSubmitted)
                GestureDetector(
                  onTap: () => provider.loadInvoice(invoice!.id!),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.refresh, color: Colors.white, size: 18),
                  ),
                ),
              const SizedBox(width: 12),
            ],
          ),

          // ─── Body ───
          Expanded(
            child: provider.loadingInvoice
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Cargando datos de origen...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : _showForm && invoice == null
                    ? _buildCreationForm()
                    : _buildInvoiceDetail(),
          ),
        ],
      ),
    );
  }

  /// Formulario de creación de la factura.
  Widget _buildCreationForm() {
    final fromReceipt = _pendingReceiptName.isNotEmpty;
    final fromPO = _pendingPOName.isNotEmpty;

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
                  icon: Icons.receipt_long_outlined,
                  bgColor: AppDesign.blueLight,
                  iconColor: AppDesign.blueIcon,
                  size: 56,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Registrar Factura de Compra',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppDesign.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fromReceipt
                      ? 'Desde la recepción — el stock ya está actualizado'
                      : fromPO
                          ? 'Directo desde la orden — actualiza inventario'
                          : 'Completá los datos para generar la factura',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── Serie de Numeración ───
          _buildSectionLabel('SERIE DE NUMERACIÓN'),
          const SizedBox(height: 6),
          Consumer<PurchaseInvoiceProvider>(
            builder: (context, piProvider, _) {
              final series = piProvider.namingSeriesOptions;
              final loaded = piProvider.catalogsLoaded;
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
                items: series
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                value: currentVal,
                onChanged: (val) =>
                    setState(() => _selectedNamingSeries = val ?? ''),
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
                    prefixIcon:
                        const Icon(Icons.business, color: AppDesign.navy),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: AppDesign.cardWhite,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                  onChanged: _searchSuppliers,
                ),
                if (_supplierSuggestions.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border:
                          Border(top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _supplierSuggestions.length,
                      itemBuilder: (context, index) {
                        final s = _supplierSuggestions[index];
                        return ListTile(
                          dense: true,
                          tileColor: Colors.transparent,
                          hoverColor: Colors.grey[200],
                          focusColor: Colors.grey[300],
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
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            s['name'] ?? '',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
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

          // ─── Nº de Factura del Proveedor (justo después del proveedor) ───
          _buildSectionLabel('Nº DE FACTURA DEL PROVEEDOR'),
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
            child: TextField(
              controller: _billNoController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Nº de Factura del Proveedor',
                hintText: 'Ej: 001-001-000123456',
                prefixIcon: const Icon(Icons.confirmation_number,
                    color: AppDesign.navy),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppDesign.cardWhite,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Fecha ───
          _buildSectionLabel('FECHA DE FACTURA'),
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
                  labelText: 'Fecha de Factura *',
                  prefixIcon:
                      const Icon(Icons.calendar_today, color: AppDesign.navy),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppDesign.cardWhite,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
                child: Text(
                  DateFormat('dd/MM/yyyy').format(_selectedDate),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ─── Almacén ───
          _buildSectionLabel('ALMACÉN'),
          const SizedBox(height: 6),
          Consumer<PurchaseInvoiceProvider>(
            builder: (context, piProvider, _) {
              final warehouses = piProvider.warehouses;
              final loaded = piProvider.catalogsLoaded;
              return _buildDropdownField(
                label: 'Almacén *',
                icon: Icons.warehouse,
                hint: !loaded ? 'Cargando...' : 'Seleccionar almacén',
                items: warehouses.map<DropdownMenuItem<String>>((w) {
                  final name = (w['name'] ?? '').toString();
                  final displayName =
                      (w['warehouse_name'] ?? name).toString();
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Text(displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                value:
                    _selectedWarehouse.isNotEmpty ? _selectedWarehouse : null,
                onChanged: (val) =>
                    setState(() => _selectedWarehouse = val ?? ''),
              );
            },
          ),

          const SizedBox(height: 16),

          // ─── Centro de Costos ───
          _buildSectionLabel('CENTRO DE COSTOS'),
          const SizedBox(height: 6),
          Consumer<PurchaseInvoiceProvider>(
            builder: (context, piProvider, _) {
              final centers = piProvider.costCenters;
              final loaded = piProvider.catalogsLoaded;
              return _buildDropdownField(
                label: 'Centro de Costos *',
                icon: Icons.account_balance,
                hint: !loaded ? 'Cargando...' : 'Seleccionar centro',
                items: centers.map<DropdownMenuItem<String>>((c) {
                  final name = (c['name'] ?? '').toString();
                  final displayName =
                      (c['cost_center_name'] ?? name).toString();
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Text(displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                value: _selectedCostCenter.isNotEmpty
                    ? _selectedCostCenter
                    : null,
                onChanged: (val) =>
                    setState(() => _selectedCostCenter = val ?? ''),
              );
            },
          ),

          const SizedBox(height: 16),

          // ─── Actualizar inventario ───
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
            child: CheckboxListTile(
              value: _updateStock,
              onChanged: (val) => setState(() => _updateStock = val ?? true),
              activeColor: AppDesign.greenIcon,
              title: const Text(
                'Actualizar inventario',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppDesign.navy,
                ),
              ),
              subtitle: Text(
                fromReceipt
                    ? 'Desmarcado — el stock ya lo actualizó la recepción'
                    : 'Marcado — la factura misma mueve el stock',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              controlAffinity: ListTileControlAffinity.trailing,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            ),
          ),

          const SizedBox(height: 24),

          // ─── Botón Crear ───
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _startCreation,
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        initialValue: value,
        hint: Text(
          hint,
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        icon: Icon(Icons.arrow_drop_down,
            size: 22, color: enabled ? AppDesign.navy : Colors.grey),
        items: items,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }

  /// Detalle de factura con escáner.
  Widget _buildInvoiceDetail() {
    final provider = context.watch<PurchaseInvoiceProvider>();
    final invoice = provider.currentInvoice;

    // Moneda de la company (fallback: $)
    final inventoryProvider = context.read<InventoryProvider>();
    final currency = inventoryProvider.companyCurrency.isNotEmpty
        ? inventoryProvider.companyCurrency
        : "\$";

    if (invoice == null) {
      return AppDesign.emptyState(
        icon: Icons.error_outline,
        title: 'Factura no disponible',
      );
    }

    return Column(
      children: [
        // ─── CÁMARA (solo si no fue enviada y no se está editando precio) ───
        if (_cameraActive && !provider.isSubmitted && !_priceEditing)
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
                        color: _isProcessingScan
                            ? AppDesign.statusDraft
                            : AppDesign.accent,
                        width: 2.5,
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: (_isProcessingScan
                                  ? AppDesign.statusDraft
                                  : AppDesign.accent)
                              .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _isProcessingScan
                              ? '📦 Pila: ${_scanQueue.length + 1} en cola...'
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

        // ─── CONTROLES ───
        if (!provider.isSubmitted)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.navy.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Cantidad
                    Container(
                      width: 64,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cant.',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Código
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: TextField(
                          controller: _scanController,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Código',
                            hintText: 'Escanear o escribir...',
                            prefixIcon: Icon(Icons.qr_code_scanner,
                                size: 18, color: Colors.grey[500]),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (v) {
                            if (v.trim().isNotEmpty) {
                              _scanQueue.add(v.trim());
                              _drainScanQueue();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Búsqueda escrita de productos
                    GestureDetector(
                      onTap: () async {
                        final row = await showItemSearchDialog(
                          context,
                          provider.erpNextService,
                          title: 'Buscar producto',
                        );
                        if (row == null || !mounted) return;
                        final qty = double.tryParse(
                              _qtyController.text.trim().replaceAll(',', '.'),
                            ) ??
                            1.0;
                        await provider.addItemToInvoiceByCode(
                          (row['name'] ?? '').toString(),
                          quantity: qty,
                        );
                        _qtyController.text = '1';
                      },
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppDesign.tealIcon,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.manage_search,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón cámara/texto
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
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppDesign.blueIcon,
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

                if (provider.lastScannedCode.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: provider.lastScanWasError
                          ? Colors.red[50]
                          : AppDesign.greenLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      provider.lastScanMessage,
                      style: TextStyle(
                        color: provider.lastScanWasError
                            ? Colors.red[800]
                            : AppDesign.greenIcon,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),

        // ─── CONTENIDO SCROLLABLE (entre controles y botones) ───
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                // ─── CÁMARA COLAPSADA (indicador al editar precios) ───
                if (_priceEditing && !_cameraActive)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _priceEditing = false;
                        _cameraActive = true;
                        _cameraController?.start();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppDesign.blueLight.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppDesign.blueIcon.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt,
                              size: 16, color: AppDesign.blueIcon),
                          const SizedBox(width: 6),
                          Text(
                            'Expandir cámara',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppDesign.blueIcon,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ─── Nº DE FACTURA DEL PROVEEDOR (editable en borrador) ───
                if (!provider.isSubmitted)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppDesign.navy.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _billNoController,
                      decoration: const InputDecoration(
                        labelText: 'Nº de Factura del Proveedor',
                        hintText: 'Ej: 001-001-000123456',
                        prefixIcon: Icon(Icons.confirmation_number,
                            color: AppDesign.navy, size: 20),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),

                // ─── INFO FACTURA ───
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
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
                        icon: invoice.updateStock
                            ? Icons.inventory_outlined
                            : Icons.inventory_2_outlined,
                        bgColor: AppDesign.tealLight,
                        iconColor: AppDesign.tealIcon,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Actualizar inventario',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[500],
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              invoice.updateStock ? 'Activado' : 'Desactivado',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: invoice.updateStock
                                    ? AppDesign.greenIcon
                                    : AppDesign.orangeIcon,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!provider.isSubmitted)
                        GestureDetector(
                          onTap: () => provider.setUpdateStock(!invoice.updateStock),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  AppDesign.blueLight.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              invoice.updateStock ? 'Desactivar' : 'Activar',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppDesign.blueIcon,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      AppDesign.statusBadge(
                        '${invoice.items.length} items — ${invoice.totalQty} uds',
                        AppDesign.blueIcon,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ─── SECCIÓN ITEMS ───
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 16, color: AppDesign.navy),
                      const SizedBox(width: 6),
                      Text(
                        'ITEMS (${invoice.items.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppDesign.navy,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ─── LISTA DE ITEMS ───
                if (invoice.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AppDesign.emptyState(
                      icon: Icons.qr_code_scanner,
                      title: 'Escaneá productos para agregar',
                      subtitle: 'Usá la cámara, escribí el código o buscá por nombre',
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: invoice.items.length,
                    itemBuilder: (context, index) {
                      return _buildItemCard(invoice.items[index], index);
                    },
                  ),

                // ─── RESUMEN: SUBTOTAL / IMPUESTO / TOTAL ───
                if (invoice.items.isNotEmpty)
                  buildTotalsSummary(
                    subtotal: invoice.subtotal,
                    tax: _effectiveTax(invoice),
                    total: _effectiveTotal(invoice),
                    currency: currency,
                  ),
              ],
            ),
          ),
        ),

        // ─── BOTÓN GUARDAR / ENVIAR ───
        if (invoice.items.isNotEmpty && !provider.isSubmitted)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: provider.isLoading ? null : _saveInvoice,
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
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppDesign.blueIcon,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
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
                            : _submitInvoice,
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text(
                          'Enviar',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: provider.isSaved
                              ? AppDesign.greenIcon
                              : Colors.grey[400],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: provider.isSaved ? 2 : 0,
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

  // ══════════════════════════════════════════════════════════
  // TOTALES (Subtotal / Impuesto / Total)
  // ══════════════════════════════════════════════════════════

  /// Impuesto efectivo a mostrar. Si el doc ya pasó por el ERP, extrapola la
  /// tasa real (impuesto / neto) al subtotal actual para que el total siga
  /// cuadrando aunque el usuario edite cantidades o precios. Si aún no se
  /// guardó, devuelve null (el ERP calcula los impuestos al guardar).
  double? _effectiveTax(PurchaseInvoice invoice) {
    if (invoice.netTotal > 0 && invoice.taxesTotal > 0) {
      return invoice.subtotal * (invoice.taxesTotal / invoice.netTotal);
    }
    if (invoice.id != null && invoice.netTotal > 0) return 0;
    return null;
  }

  /// Total efectivo: subtotal en vivo + impuesto efectivo (o null si aún
  /// no hay datos del ERP).
  double? _effectiveTotal(PurchaseInvoice invoice) {
    final tax = _effectiveTax(invoice);
    if (tax == null) return null;
    return invoice.subtotal + tax;
  }

  /// Paso de los botones +/-: 0.5 si la UOM admite decimales, 1 si no.
  double _piStep(PurchaseInvoiceProvider provider, PurchaseInvoiceItem item) {
    return provider.erpNextService.uomAllowsDecimals(_uomOf(provider, item))
        ? 0.5
        : 1.0;
  }

  /// UOM del item (del item mismo o resuelta desde la caché).
  String _uomOf(PurchaseInvoiceProvider provider, PurchaseInvoiceItem item) {
    if (item.uom.isNotEmpty) return item.uom;
    final cached = provider.itemsByCode[item.itemCode.toUpperCase()];
    return cached?.stockUom ?? '';
  }

  Widget _buildItemCard(PurchaseInvoiceItem item, int index) {
    final provider = context.read<PurchaseInvoiceProvider>();
    final readOnly = provider.isSubmitted;

    // Moneda de la company (fallback: $)
    final inventoryProvider = context.read<InventoryProvider>();
    final currency = inventoryProvider.companyCurrency.isNotEmpty
        ? inventoryProvider.companyCurrency
        : "\$";

    // Limpiar controllers de items que ya no existen
    _cleanupRateControllers(provider.currentInvoice?.items ?? []);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      decoration: BoxDecoration(
        color: readOnly ? Colors.grey[100] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppDesign.navy.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila principal: avatar + nombre + controles cantidad
            Row(
              children: [
                // Avatar
                AppDesign.circleAvatar(
                  icon: Icons.inventory_2_outlined,
                  bgColor:
                      readOnly ? Colors.grey[200]! : AppDesign.tealLight,
                  iconColor:
                      readOnly ? Colors.grey[500]! : AppDesign.tealIcon,
                  size: 36,
                ),
                const SizedBox(width: 10),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName.isNotEmpty ? item.itemName : item.itemCode,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: readOnly ? Colors.grey[600] : AppDesign.navy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.itemCode,
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Controles cantidad
                if (readOnly)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppDesign.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      fmtQty(item.qty),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppDesign.navy,
                      ),
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => provider.updateItemQty(
                            index, item.qty - _piStep(provider, item)),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.remove,
                              size: 16, color: Colors.red),
                        ),
                      ),
                      GestureDetector(
                        // Tap en la cantidad: edición exacta (decimales si la UOM lo permite)
                        onTap: () async {
                          final uom = _uomOf(provider, item);
                          final allows =
                              provider.erpNextService.uomAllowsDecimals(uom);
                          final newQty = await showQtyInputDialog(
                            context,
                            current: item.qty,
                            allowsDecimals: allows,
                            uom: uom,
                          );
                          if (newQty != null) {
                            provider.updateItemQty(index, newQty);
                          }
                        },
                        child: Container(
                          width: 40,
                          alignment: Alignment.center,
                          child: Text(
                            fmtQty(item.qty),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppDesign.navy,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => provider.updateItemQty(
                            index, item.qty + _piStep(provider, item)),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppDesign.greenIcon.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add,
                              size: 16, color: AppDesign.greenIcon),
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            // Fila de precio (editable en borrador)
            if (!readOnly) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppDesign.blueLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Precio',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[600],
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          TextField(
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              prefixText: '$currency ',
                              prefixStyle: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                            controller: _getRateController(
                                item.itemCode, item.rate),
                            onChanged: (val) {
                              final parsed = double.tryParse(val) ?? 0.0;
                              provider.updateItemRate(index, parsed);
                            },
                            onTap: () {
                              if (!_priceEditing) {
                                setState(() {
                                  _priceEditing = true;
                                  _cameraActive = false;
                                  _cameraController?.stop();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Si ya está enviado, solo mostrar valores
            if (readOnly) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Precio',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[600])),
                          Text(
                            item.rate > 0
                                ? '$currency${item.rate.toStringAsFixed(2)}'
                                : '-',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppDesign.navy),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
