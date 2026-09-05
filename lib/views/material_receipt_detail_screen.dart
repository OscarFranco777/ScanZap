import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/material_receipt_provider.dart';
import '../models/material_receipt.dart';

/// Pantalla de creación y detalle de Recepción de Mercadería.
/// Incluye escáner de cámara y entrada manual.
class MaterialReceiptDetailScreen extends StatefulWidget {
  const MaterialReceiptDetailScreen({super.key});

  @override
  State<MaterialReceiptDetailScreen> createState() =>
      _MaterialReceiptDetailScreenState();
}

class _MaterialReceiptDetailScreenState
    extends State<MaterialReceiptDetailScreen> {
  // ─── Cámara ───
  MobileScannerController? _cameraController;
  bool _cameraActive = true;
  bool _scanLocked = false;
  String _lastScannedCode = '';
  Timer? _lockTimer;

  // ─── Formulario ───
  final _scanController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  bool _showForm = true;

  // ─── Campos ───
  String _selectedWarehouse = '';

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
      final mrProvider = context.read<MaterialReceiptProvider>();
      mrProvider.loadItemsCache(inventoryProvider.itemsByCode);
      mrProvider.fetchCatalogs();
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _lockTimer?.cancel();
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

    final provider = context.read<MaterialReceiptProvider>();
    final qty = int.tryParse(_qtyController.text.trim()) ?? 1;
    provider.scanItemToReceipt(code, quantity: qty);
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

  void _startDirectCreation() {
    if (_selectedWarehouse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Seleccioná un almacén destino'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final provider = context.read<MaterialReceiptProvider>();
    provider.createNewReceipt(warehouse: _selectedWarehouse);
    setState(() => _showForm = false);
  }

  Future<void> _saveReceipt() async {
    final provider = context.read<MaterialReceiptProvider>();
    final ok = await provider.saveReceipt();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💾 Borrador guardado: ${provider.currentReceipt?.id ?? ''}',
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

  Future<void> _submitReceipt() async {
    final provider = context.read<MaterialReceiptProvider>();

    if (!provider.isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Primero guardá la recepción como borrador'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar recepción'),
        content: const Text(
          '¿Confirmás que querés enviar esta recepción a ERPNext? No podrá modificarse después.',
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

    final ok = await provider.submitReceipt();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Recepción ${provider.currentReceipt?.id ?? ''} enviada',
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
    final provider = context.watch<MaterialReceiptProvider>();
    final receipt = provider.currentReceipt;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          receipt?.id != null ? '📦 ${receipt!.id}' : '📦 Nueva Recepción',
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
          if (receipt?.id != null && !provider.isSubmitted)
            IconButton(
              onPressed: () => provider.refreshReceipt(),
              icon: const Icon(Icons.refresh),
              tooltip: 'Refrescar',
            ),
        ],
      ),
      body: _showForm && receipt == null
          ? _buildCreationForm()
          : _buildReceiptDetail(),
    );
  }

  /// Formulario de creación (recepción directa).
  Widget _buildCreationForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 8),
          Text(
            'Crear Recepción de Mercadería',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Almacén destino
          Consumer<MaterialReceiptProvider>(
            builder: (context, mrProvider, _) {
              final warehouses = mrProvider.warehouses;
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
                initialValue: _selectedWarehouse.isNotEmpty
                    ? _selectedWarehouse
                    : null,
                hint: Text(
                  'Seleccioná almacén',
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
          const SizedBox(height: 16),

          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _startDirectCreation,
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

  /// Detalle de recepción con escáner.
  Widget _buildReceiptDetail() {
    final provider = context.watch<MaterialReceiptProvider>();
    final receipt = provider.currentReceipt;

    if (receipt == null) {
      return const Center(child: Text('Recepción no disponible'));
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

        // ─── CONTROLES ───
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

        // ─── INFO RECEPCIÓN ───
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.grey[100],
          child: Row(
            children: [
              Icon(Icons.warehouse, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  receipt.warehouse.isNotEmpty
                      ? receipt.warehouse
                      : 'Sin almacén',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[800],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${receipt.items.length} items — ${receipt.totalQty} uds',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // ─── LISTA DE ITEMS ───
        Expanded(
          child: receipt.items.isEmpty
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
                  itemCount: receipt.items.length,
                  itemBuilder: (context, index) {
                    return _buildItemCard(receipt.items[index], index);
                  },
                ),
        ),

        // ─── BOTÓN GUARDAR / ENVIAR ───
        if (receipt.items.isNotEmpty && !provider.isSubmitted)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: provider.isLoading ? null : _saveReceipt,
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
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: (provider.isLoading || !provider.isSaved)
                            ? null
                            : _submitReceipt,
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
      ],
    );
  }

  Widget _buildItemCard(MaterialReceiptItem item, int index) {
    final provider = context.read<MaterialReceiptProvider>();
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
