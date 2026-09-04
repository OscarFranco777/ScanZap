import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/purchase_order_provider.dart';
import '../models/purchase_order.dart';

/// Pantalla de creación y detalle de Orden de Compra.
/// Incluye escáner de cámara y entrada manual.
class PurchaseOrderDetailScreen extends StatefulWidget {
  const PurchaseOrderDetailScreen({super.key});

  @override
  State<PurchaseOrderDetailScreen> createState() => _PurchaseOrderDetailScreenState();
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
    _lockTimer?.cancel();
    _supplierController.dispose();
    _scanController.dispose();
    _qtyController.dispose();
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

    final provider = context.read<PurchaseOrderProvider>();
    provider.createNewOrder(
      supplier: _supplierController.text.trim(),
      supplierId: _selectedSupplierId,
      date: _selectedDate,
      costCenter: _selectedCostCenter,
      setWarehouse: _selectedWarehouse,
    );

    setState(() => _showForm = false);
  }

  Future<void> _submitOrder() async {
    final provider = context.read<PurchaseOrderProvider>();
    final ok = await provider.submitOrder();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Orden ${provider.currentOrder?.id ?? ''} creada'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
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
    final provider = context.watch<PurchaseOrderProvider>();
    final order = provider.currentOrder;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          order?.id != null ? '📦 ${order!.id}' : '🛒 Nueva Orden',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (order?.id != null)
            IconButton(
              onPressed: () => provider.refreshOrder(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refrescar',
            ),
          if (order != null && order.items.isNotEmpty)
            IconButton(
              onPressed: _submitOrder,
              icon: const Icon(Icons.send),
              tooltip: 'Enviar a ERPNext',
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
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.shopping_cart_checkout, size: 64, color: Theme.of(context).primaryColor),
          const SizedBox(height: 16),
          Text(
            'Crear Orden de Compra',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Proveedor
          TextField(
            controller: _supplierController,
            decoration: const InputDecoration(
              labelText: 'Proveedor *',
              hintText: 'Escribí el nombre del proveedor',
              prefixIcon: Icon(Icons.business),
              border: OutlineInputBorder(),
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
                    title: Text(s['supplier_name'] ?? s['name'] ?? ''),
                    subtitle: Text(s['name'] ?? '', style: const TextStyle(fontSize: 11)),
                    onTap: () {
                      _supplierController.text = s['supplier_name'] ?? s['name'] ?? '';
                      _selectedSupplierId = s['name'] ?? '';
                      setState(() => _supplierSuggestions = []);
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 16),

          // Fecha
          InkWell(
            onTap: _selectDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de Entrega *',
                prefixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder(),
              ),
              child: Text(
                DateFormat('dd/MM/yyyy').format(_selectedDate),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Almacén Destino ───
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final warehouses = poProvider.warehouses;
              final loaded = poProvider.catalogsLoaded;
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Almacén Destino *',
                  prefixIcon: Icon(Icons.warehouse),
                  border: OutlineInputBorder(),
                ),
                value: _selectedWarehouse.isNotEmpty ? _selectedWarehouse : null,
                hint: Text(
                  !loaded ? 'Cargando...' : 'Seleccioná un almacén',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                items: warehouses.map<DropdownMenuItem<String>>((w) {
                  final name = w['name'] ?? '';
                  final displayName = w['warehouse_name'] ?? name;
                  return DropdownMenuItem(
                    value: name,
                    child: Text(displayName, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedWarehouse = val ?? '');
                },
              );
            },
          ),
          const SizedBox(height: 16),

          // ─── Centro de Costos ───
          Consumer<PurchaseOrderProvider>(
            builder: (context, poProvider, _) {
              final centers = poProvider.costCenters;
              final loaded = poProvider.catalogsLoaded;
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Centro de Costos *',
                  prefixIcon: Icon(Icons.account_balance),
                  border: OutlineInputBorder(),
                ),
                value: _selectedCostCenter.isNotEmpty ? _selectedCostCenter : null,
                hint: Text(
                  !loaded ? 'Cargando...' : 'Seleccioná un centro de costos',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                items: centers.map<DropdownMenuItem<String>>((c) {
                  final name = c['name'] ?? '';
                  final displayName = c['cost_center_name'] ?? name;
                  return DropdownMenuItem(
                    value: name,
                    child: Text(displayName, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedCostCenter = val ?? '');
                },
              );
            },
          ),
          const SizedBox(height: 32),

          // Botón crear
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _createOrder,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Crear y Escanear'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(fontSize: 16),
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

    return Column(
      children: [
        // ─── CÁMARA ───
        if (_cameraActive)
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: (_scanLocked ? Colors.orange : Colors.blue).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        labelText: 'Cant.',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                    icon: Icon(_cameraActive ? Icons.camera_alt : Icons.keyboard),
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
                    color: provider.lastScanWasError ? Colors.red[50] : Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    provider.lastScanMessage,
                    style: TextStyle(
                      color: provider.lastScanWasError ? Colors.red[800] : Colors.green[800],
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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey[800]),
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
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange[800]),
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
                      Icon(Icons.qr_code_scanner, size: 48, color: Colors.grey[300]),
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

        // ─── BOTÓN ENVIAR ───
        if (order.items.isNotEmpty)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: provider.isLoading ? null : _submitOrder,
                  icon: provider.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    provider.isLoading ? 'Enviando...' : 'Enviar Orden a ERPNext',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemCard(PurchaseOrderItem item, int index) {
    final provider = context.read<PurchaseOrderProvider>();

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
                    item.itemName.isNotEmpty ? item.itemName : item.itemCode,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => provider.updateItemQty(index, item.qty - 1),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: Colors.red,
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                Container(
                  width: 36,
                  alignment: Alignment.center,
                  child: Text(
                    '${item.qty}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => provider.updateItemQty(index, item.qty + 1),
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
  }
}
