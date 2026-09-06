import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/material_receipt_provider.dart';
import '../models/material_receipt.dart';
import '../theme/app_design.dart';

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
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── Header navy ───
          AppDesign.buildHeader(
            title: receipt?.id != null ? '📦 ${receipt!.id}' : '📦 Nueva Recepción',
            subtitle: provider.isSubmitted
                ? 'Recepción enviada a ERPNext'
                : receipt?.id != null
                    ? 'Recepción en borrador'
                    : 'Crear nueva recepción',
            icon: Icons.local_shipping_outlined,
            onBack: () => Navigator.pop(context),
            actions: [
              if (provider.isSubmitted)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppDesign.statusSubmitted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 13, color: AppDesign.statusSubmitted),
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
              if (receipt?.id != null && !provider.isSubmitted)
                GestureDetector(
                  onTap: () => provider.refreshReceipt(),
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
              const SizedBox(width: 12),
            ],
          ),

          // ─── Body ───
          Expanded(
            child: _showForm && receipt == null
                ? _buildCreationForm()
                : _buildReceiptDetail(),
          ),
        ],
      ),
    );
  }

  /// Formulario de creación (recepción directa).
  Widget _buildCreationForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Icono y título ───
          Center(
            child: AppDesign.circleAvatar(
              icon: Icons.inventory_2_outlined,
              bgColor: AppDesign.tealLight,
              iconColor: AppDesign.tealIcon,
              size: 56,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Crear Recepción de Mercadería',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppDesign.navy,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Seleccioná el almacén destino para empezar',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // ─── Almacén destino ───
          Container(
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
            padding: const EdgeInsets.all(16),
            child: Consumer<MaterialReceiptProvider>(
              builder: (context, mrProvider, _) {
                final warehouses = mrProvider.warehouses;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppDesign.circleAvatar(
                          icon: Icons.warehouse_outlined,
                          bgColor: AppDesign.tealLight,
                          iconColor: AppDesign.tealIcon,
                          size: 32,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Almacén Destino *',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppDesign.navy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
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
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // ─── Botón crear ───
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppDesign.navy.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _startDirectCreation,
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: const Text(
                  'Crear y Escanear',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppDesign.navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
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
      return AppDesign.emptyState(
        icon: Icons.error_outline,
        title: 'Recepción no disponible',
      );
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
                        color: _scanLocked ? AppDesign.statusDraft : AppDesign.accent,
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
                          color: (_scanLocked ? AppDesign.statusDraft : AppDesign.accent)
                              .withValues(alpha: 0.9),
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
                        keyboardType: TextInputType.number,
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
                            prefixIcon: Icon(Icons.qr_code_scanner, size: 18, color: Colors.grey[500]),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (v) {
                            if (v.trim().isNotEmpty) _processScan(v);
                          },
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

        const SizedBox(height: 8),

        // ─── INFO RECEPCIÓN ───
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                icon: Icons.warehouse_outlined,
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
                      'Almacén',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      receipt.warehouse.isNotEmpty
                          ? receipt.warehouse
                          : 'Sin almacén',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppDesign.navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppDesign.statusBadge(
                '${receipt.items.length} items — ${receipt.totalQty} uds',
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
              const Icon(Icons.inventory_2_outlined, size: 16, color: AppDesign.navy),
              const SizedBox(width: 6),
              Text(
                'ITEMS (${receipt.items.length})',
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
        Expanded(
          child: receipt.items.isEmpty
              ? AppDesign.emptyState(
                  icon: Icons.qr_code_scanner,
                  title: 'Escaneá productos para agregar',
                  subtitle: 'Usá la cámara o escribí el código',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                            : const Icon(Icons.save, size: 18),
                        label: Text(
                          provider.isSaved ? 'Actualizar' : 'Guardar',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
                            : _submitReceipt,
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text(
                          'Enviar',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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

  Widget _buildItemCard(MaterialReceiptItem item, int index) {
    final provider = context.read<MaterialReceiptProvider>();
    final readOnly = provider.isSubmitted;

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
        child: Row(
          children: [
            // Avatar
            AppDesign.circleAvatar(
              icon: Icons.inventory_2_outlined,
              bgColor: readOnly ? Colors.grey[200]! : AppDesign.tealLight,
              iconColor: readOnly ? Colors.grey[500]! : AppDesign.tealIcon,
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
            // Controles
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
                    onTap: () => provider.updateItemQty(index, item.qty - 1),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.remove, size: 16, color: Colors.red),
                    ),
                  ),
                  Container(
                    width: 40,
                    alignment: Alignment.center,
                    child: Text(
                      '${item.qty}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppDesign.navy,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => provider.updateItemQty(index, item.qty + 1),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppDesign.greenIcon.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, size: 16, color: AppDesign.greenIcon),
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
