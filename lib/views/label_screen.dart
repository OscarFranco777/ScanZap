import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../providers/label_provider.dart';
import '../providers/inventory_provider.dart';
import '../theme/app_design.dart';

/// Módulo de Etiquetas de Precio: escanear producto → traer precio de la
/// lista configurada → imprimir etiqueta por Bluetooth.
class LabelScreen extends StatefulWidget {
  const LabelScreen({super.key});

  @override
  State<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends State<LabelScreen> {
  // ─── Cámara ───
  MobileScannerController? _cameraController;
  bool _cameraActive = true;

  // ─── Debounce / Lock ───
  bool _scanLocked = false;
  String _lastScannedCode = '';
  Timer? _lockTimer;
  static const _lockDuration = Duration(seconds: 2);

  // ─── Manual ───
  final _manualController = TextEditingController();

  // ─── Copias ───
  int _copies = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final labelProvider = context.read<LabelProvider>();
    await labelProvider.loadSettings();
    _copies = labelProvider.settings.copies;
    // La configuración (impresora, lista de precios, tipo de etiqueta) vive
    // en la pantalla de Configuración principal; acá solo la consumimos.
    if (labelProvider.priceLists.isEmpty) {
      labelProvider.loadPriceLists();
    }
    // Sincronizar la plantilla del diseño con el ERP (si hay sesión):
    // el diseño es único para todos los dispositivos.
    labelProvider.syncTemplateFromErp();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _cameraController?.dispose();
    _manualController.dispose();
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
    HapticFeedback.mediumImpact();

    _resolve(code);

    _lockTimer?.cancel();
    _lockTimer = Timer(_lockDuration, () {
      _scanLocked = false;
      _lastScannedCode = '';
      if (_cameraActive && mounted) {
        _cameraController?.start();
      }
    });
  }

  Future<void> _resolve(String code) async {
    final labelProvider = context.read<LabelProvider>();
    final inventory = context.read<InventoryProvider>();
    await labelProvider.resolveCode(code, inventory);
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bg = AppDesign.bg;
    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          AppDesign.buildHeader(
            title: 'Etiquetas de Precio',
            subtitle: 'Escaneá → precio → imprimí',
            icon: Icons.price_check,
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: Consumer<LabelProvider>(
              builder: (context, lp, _) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildConfigStatus(lp),
                    const SizedBox(height: 16),
                    _buildScanZone(lp),
                    const SizedBox(height: 16),
                    _buildResultCard(lp),
                    const SizedBox(height: 16),
                    _buildHistory(lp),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── ESTADO DE CONFIGURACIÓN ───

  /// Barra compacta con la config activa + acceso a la pantalla de
  /// Configuración (donde vive ahora la configuración del módulo).
  Widget _buildConfigStatus(LabelProvider lp) {
    // Verde SOLO cuando la impresora está configurada; la lista de precios
    // se muestra como info pero no decide el color.
    final configured = lp.settings.printerMac.isNotEmpty;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/config'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: configured
              ? Colors.green.withValues(alpha: 0.08)
              : Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: configured
                ? Colors.green.withValues(alpha: 0.4)
                : Colors.orange.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              configured ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 20,
              color: configured ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                configured
                    ? (lp.settings.priceList.isEmpty
                        ? lp.settings.printerName
                        : '${lp.settings.printerName} • ${lp.settings.priceList}')
                    : 'Configurá la impresora en Configuración',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: configured ? Colors.green[800] : Colors.orange[900],
                ),
              ),
            ),
            Icon(Icons.settings_outlined,
                size: 18, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  // ─── ESCANEO ───

  Widget _buildScanZone(LabelProvider lp) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
                  decoration: InputDecoration(
                    hintText: 'Escaneá o escribí el código...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (code) {
                    _resolve(code);
                    _manualController.clear();
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () {
                  _resolve(_manualController.text);
                  _manualController.clear();
                },
                style: IconButton.styleFrom(
                  backgroundColor: AppDesign.navy,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _cameraActive = !_cameraActive;
                    if (_cameraActive) {
                      _cameraController ??= MobileScannerController(
                        detectionSpeed: DetectionSpeed.noDuplicates,
                        facing: CameraFacing.back,
                      );
                      _cameraController?.start();
                    } else {
                      _cameraController?.stop();
                    }
                  });
                },
                style: IconButton.styleFrom(
                  backgroundColor: _cameraActive
                      ? Colors.orange.withValues(alpha: 0.15)
                      : AppDesign.bg,
                  foregroundColor: _cameraActive ? Colors.orange : Colors.grey,
                ),
                icon: Icon(_cameraActive ? Icons.camera_alt : Icons.no_photography),
              ),
            ],
          ),
          if (_cameraActive) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 180,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cameraController != null)
                      MobileScanner(
                        controller: _cameraController!,
                        onDetect: _onBarcodeDetected,
                      ),
                    if (_scanLocked)
                      Container(
                        color: Colors.orange.withValues(alpha: 0.15),
                        child: const Center(
                          child: Text(
                            '⏳ Buscando...',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── RESULTADO ───

  Widget _buildResultCard(LabelProvider lp) {
    if (lp.searchingItem) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (lp.searchMessage.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: Text(
          lp.searchMessage,
          style: TextStyle(color: Colors.orange[900]),
        ),
      );
    }

    final item = lp.currentItem;
    if (item == null) {
      return AppDesign.emptyState(
        icon: Icons.price_check,
        title: 'Escaneá un producto',
        subtitle:
            'Apuntá la cámara al código de barras o escribilo para traer '
            'el precio y imprimir la etiqueta.',
      );
    }

    final price = lp.currentItemPrice;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppDesign.accent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            item.itemName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppDesign.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.itemCode} • ${item.stockUom}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          if (price != null)
            Text(
              lp.formatPrice(price),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: AppDesign.navy,
              ),
            )
          else
            Text(
              'Sin precio en "${lp.settings.priceList}"',
              style: TextStyle(fontSize: 13, color: Colors.orange[800]),
            ),
          const SizedBox(height: 12),
          // Copias
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _copies > 1
                    ? () => setState(() => _copies--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$_copies etiqueta${_copies > 1 ? 's' : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _copies++),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: lp.isPrinting
                  ? null
                  : () => lp.printCurrentItem(copies: _copies),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesign.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: lp.isPrinting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.print),
              label: Text(
                lp.isPrinting ? 'Imprimiendo...' : '🖨️ Imprimir',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (lp.lastPrintMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              lp.lastPrintMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: lp.lastPrintWasError
                    ? Colors.red
                    : Colors.green.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── HISTORIAL ───

  Widget _buildHistory(LabelProvider lp) {
    if (lp.history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IMPRESAS EN ESTA SESIÓN',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.grey[700],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...lp.history.take(10).map((h) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.label, size: 18, color: AppDesign.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '${h.itemCode} • ${h.copies} copia(s)',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${h.at.hour.toString().padLeft(2, '0')}:${h.at.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
