import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/inventory_provider.dart';
import '../models/inventory_row.dart';

/// Terminal de escaneo de código de barras con cámara del dispositivo.
/// Optimizada para dispositivos de gama baja/media.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  // ─── Controllers ───
  final _scanController = TextEditingController();
  final _focusNode = FocusNode();
  final _manualController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');

  // ─── Cámara ───
  MobileScannerController? _cameraController;
  bool _cameraActive = true;

  // ─── Debounce / Lock ───
  bool _scanLocked = false;
  String _lastScannedCode = '';

  // ─── Timers ───
  Timer? _lockTimer;

  // ─── Duración del lock post-escaneo: 2 segundos ───
  static const _lockDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _lockTimer?.cancel();
    _scanController.dispose();
    _manualController.dispose();
    _focusNode.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════
  // LÓGICA DE ESCANEO
  // ══════════════════════════════════════════════════════════════

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_scanLocked) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final code = barcode.rawValue!.trim();
    if (code.isEmpty) return;

    if (code == _lastScannedCode) return;

    _scanLocked = true;
    _lastScannedCode = code;

    // Pausar cámara — reduce calentamiento
    _cameraController?.stop();

    _processScanInternal(code);
  }

  Future<void> _processScanInternal(String code) async {
    HapticFeedback.mediumImpact();

    final provider = context.read<InventoryProvider>();
    final qty = _getQty();
    await provider.scanItem(code, quantity: qty);

    _qtyController.text = '1';

    _lockTimer?.cancel();
    _lockTimer = Timer(_lockDuration, () {
      _scanLocked = false;
      _lastScannedCode = '';
      if (_cameraActive && mounted) {
        _cameraController?.start();
      }
    });
  }

  Future<void> _processScan(String code) async {
    if (code.trim().isEmpty) return;

    final provider = context.read<InventoryProvider>();
    final qty = _getQty();
    await provider.scanItem(code, quantity: qty);
    _scanController.clear();
    _qtyController.text = '1';
  }

  int _getQty() {
    final parsed = int.tryParse(_qtyController.text.trim());
    return (parsed != null && parsed > 0) ? parsed : 1;
  }

  // ══════════════════════════════════════════════════════════════
  // ACCIONES
  // ══════════════════════════════════════════════════════════════

  void _shareReport() async {
    final provider = context.read<InventoryProvider>();
    final excelBytes = provider.generateExcelReport();
    if (excelBytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No hay productos para compartir'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'inventario_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(excelBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '📦 Reporte de inventario - ${now.day}/${now.month}/${now.year}',
        subject: 'Inventario Superzito',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al compartir: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleCamera() {
    setState(() {
      _cameraActive = !_cameraActive;
      if (_cameraActive) {
        _cameraController?.start();
      } else {
        _cameraController?.stop();
      }
    });
  }

  void _toggleTorch() {
    _cameraController?.toggleTorch();
    setState(() {});
  }

  void _refreshItems() async {
    final provider = context.read<InventoryProvider>();
    final countBefore = provider.allItems.length;
    await provider.refreshItems();
    final countAfter = provider.allItems.length;
    if (!mounted) return;
    final newItems = countAfter - countBefore;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newItems > 0
            ? '✅ Se encontraron $newItems productos nuevos (total: $countAfter)'
            : '🔄 Lista actualizada ($countAfter productos) — sin cambios'),
        backgroundColor: newItems > 0 ? Colors.green : Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showManualEntry() {
    final qtyCtrl = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📝 Entrada Manual'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _manualController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Código del producto',
                  hintText: 'Escribí o pegá el código',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cantidad',
                  hintText: '1',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
              _qtyController.text = '$qty';
              _processScan(_manualController.text);
              _manualController.clear();
            },
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════════

  /// Altura de cámara adaptativa — gama baja/media.
  double _getCameraHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    if (h < 600) return h * 0.22;
    if (h < 700) return h * 0.25;
    return h * 0.28;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final scanned = provider.scannedItems;
    final screenW = MediaQuery.of(context).size.width;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          '📦 Inventario — ${provider.uniqueProducts} productos',
          style: TextStyle(fontSize: screenW < 360 ? 14 : 16),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${provider.totalUnitsScanned} uds | L${provider.totalInventoryValue.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: screenW < 360 ? 11 : 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ─── ZONA DE CÁMARA ───
            if (_cameraActive)
              SizedBox(
                height: _getCameraHeight(context),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cameraController != null)
                      MobileScanner(
                        controller: _cameraController!,
                        onDetect: _onBarcodeDetected,
                      ),
                    // Borde de cámara
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
                              color: _scanLocked
                                  ? Colors.orange.withOpacity(0.9)
                                  : Colors.blue.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _scanLocked
                                  ? '⏳ Esperá...'
                                  : '📷 Apuntá al código',
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
                    // Botones de cámara — posicionados dentro del área visible
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _camButton(
                            icon: _cameraController?.torchEnabled == true
                                ? Icons.flash_on
                                : Icons.flash_off,
                            onTap: _toggleTorch,
                            tooltip: 'Linterna',
                          ),
                          const SizedBox(height: 4),
                          _camButton(
                            icon: _cameraActive
                                ? Icons.videocam
                                : Icons.videocam_off,
                            onTap: _toggleCamera,
                            tooltip: _cameraActive ? 'Apagar cámara' : 'Prender cámara',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // ─── CONTROLES + LISTA — scrolleable ───
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ─── Campos de entrada ───
                    Container(
                      color: Colors.blue[50],
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              // Campo cantidad — más ancho para 4 dígitos
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
                                    hintText: '1',
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
                              // Campo código
                              Expanded(
                                child: TextField(
                                  controller: _scanController,
                                  focusNode: _focusNode,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    labelText: 'Código',
                                    hintText: 'Escanear...',
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
                                  onSubmitted: _processScan,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Botón entrada manual
                              IconButton(
                                onPressed: _showManualEntry,
                                icon: const Icon(Icons.edit, size: 20),
                                tooltip: 'Entrada manual',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: const Size(36, 36),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Último escaneo
                          if (provider.lastScannedCode.isNotEmpty)
                            Container(
                              width: double.infinity,
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

                    // ─── BOTONES DE ACCIÓN — sin cortar texto ───
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        children: [
                          _actionButton(
                            icon: Icons.share,
                            label: 'Compartir',
                            onTap: _shareReport,
                          ),
                          const SizedBox(width: 6),
                          _actionButton(
                            icon: Icons.upload_file,
                            label: 'Costos\nExcel',
                            onTap: () => Navigator.of(context).pushNamed('/excel'),
                          ),
                          const SizedBox(width: 6),
                          _actionButton(
                            icon: Icons.table_chart,
                            label: 'Ver\nReporte',
                            onTap: () => Navigator.of(context).pushNamed('/report'),
                          ),
                          const SizedBox(width: 6),
                          _actionButton(
                            icon: Icons.delete_sweep,
                            label: 'Limpiar',
                            color: Colors.red,
                            onTap: _confirmClear,
                          ),
                        ],
                      ),
                    ),

                    // Botón refrescar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed:
                              provider.isLoadingItems ? null : _refreshItems,
                          icon: provider.isLoadingItems
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh, size: 14),
                          label: Text(
                            provider.isLoadingItems
                                ? 'Actualizando...'
                                : '🔄 Refrescar productos',
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                          ),
                        ),
                      ),
                    ),

                    const Divider(height: 1),

                    // ─── LISTA DE PRODUCTOS ESCANEADOS ───
                    if (scanned.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner,
                              size: 60,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Escanee un código de barras',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              'o use la entrada manual',
                              style: TextStyle(color: Colors.grey[400], fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.builder(
                        itemCount: scanned.length,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemBuilder: (context, index) {
                          final row = scanned[index];
                          return _buildItemCard(row, provider);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Botón de cámara (overlay) ───
  Widget _camButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  // ─── Botón de acción (debajo de cámara) ───
  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? Colors.blue[700]!;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: c.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: c),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemCard(InventoryRow row, InventoryProvider provider) {
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
                    row.itemName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${row.displayCode} — ${row.stockUom}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                  Text(
                    row.hasCost
                        ? 'L${row.unitCost.toStringAsFixed(2)} /ud → L${row.totalCost.toStringAsFixed(2)}'
                        : '⚠️ Sin costo',
                    style: TextStyle(
                      color: row.hasCost ? Colors.teal[70] : Colors.orange[800],
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => provider.decrementQuantity(row.itemCode),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  color: Colors.red,
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                Container(
                  width: 36,
                  alignment: Alignment.center,
                  child: Text(
                    '${row.quantity}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => provider.incrementQuantity(row.itemCode),
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

  void _confirmClear() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Limpiar Sesión'),
        content: const Text(
          '¿Borrar todos los productos escaneados? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<InventoryProvider>().clearSession();
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Limpiar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
