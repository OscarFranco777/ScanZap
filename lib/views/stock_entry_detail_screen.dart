import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/inventory_provider.dart';
import '../providers/stock_entry_provider.dart';
import '../models/stock_entry.dart';
import '../theme/app_design.dart';
import 'ui_helpers.dart';

/// Pantalla de creación y detalle de Entrada de Inventario (Stock Entry).
/// Copia la lógica de la Recepción de Mercadería: escáner en modo pila LIFO,
/// búsqueda escrita y cantidades con decimales según la UOM del producto.
///
/// Cabecera: Tipo de Entrada de Stock (del ERP), Centro de Costos (se pega
/// en cada fila), Almacén Origen y Destino, y Observaciones.
/// Sin precios: el costo lo pone el ERP según el tipo de movimiento.
class StockEntryDetailScreen extends StatefulWidget {
  const StockEntryDetailScreen({super.key});

  @override
  State<StockEntryDetailScreen> createState() =>
      _StockEntryDetailScreenState();
}

class _StockEntryDetailScreenState
    extends State<StockEntryDetailScreen> {
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
  final _remarksController = TextEditingController();
  final _scanController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  bool _showForm = true;

  // ─── Precio base (solo Material Receipt) ───
  // Un controller por item_code; _priceEditing evita pisar el campo que el
  // usuario está editando (y apaga la cámara mientras escribe, como la
  // Factura de Compra).
  final Map<String, TextEditingController> _rateControllers = {};
  bool _priceEditing = false;

  // ─── Campos ───
  String _selectedEntryType = '';
  String _selectedSourceWarehouse = '';
  String _selectedTargetWarehouse = '';
  String _selectedCostCenter = '';
  String _selectedNamingSeries = '';
  DateTime _selectedDate = DateTime.now();

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
      final seProvider = context.read<StockEntryProvider>();
      seProvider.loadItemsCache(inventoryProvider.itemsByCode);
      seProvider.fetchCatalogs().then((_) async {
        // Si no hay serie seleccionada, usar la primera disponible
        if (mounted &&
            _selectedNamingSeries.isEmpty &&
            seProvider.namingSeriesOptions.isNotEmpty) {
          setState(() =>
              _selectedNamingSeries = seProvider.namingSeriesOptions.first);
        }
        // Si la conexión terminó después de abrir esta pantalla, esperar a
        // que carguen los items del inventario y recargar el cache.
        if (mounted && seProvider.itemsByCode.isEmpty) {
          for (var i = 0;
              i < 30 && inventoryProvider.itemsByCode.isEmpty;
              i++) {
            await Future.delayed(const Duration(seconds: 1));
          }
          if (mounted) seProvider.loadItemsCache(inventoryProvider.itemsByCode);
        }
      });
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

  /// Sincroniza los controllers de precio con los valores reales del ERP
  /// (tras guardar, el ERP ajusta el costo). No pisa el campo que el
  /// usuario está editando en este momento.
  void _syncRateControllers(StockEntryProvider provider) {
    if (_priceEditing) return; // no pisar lo que el usuario está editando
    for (final item in provider.currentEntry?.items ?? []) {
      final c = _rateControllers[item.itemCode];
      if (c == null) continue;
      c.text = item.basicRate > 0 ? item.basicRate.toStringAsFixed(2) : '';
    }
  }

  void _cleanupRateControllers(List<StockEntryItem> items) {
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
    _remarksController.dispose();
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
        final provider = context.read<StockEntryProvider>();
        final qty = parseFlexibleNumber(_qtyController.text) ?? 1.0;
        await provider.scanItemToEntry(code, quantity: qty);
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

  void _startCreation() {
    if (_selectedEntryType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ Seleccioná el tipo de entrada'),
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

    // Material Transfer necesita ambos almacenes; Receipt solo destino;
    // Issue solo origen.
    if (_selectedEntryType == 'Material Transfer' &&
        (_selectedSourceWarehouse.isEmpty ||
            _selectedTargetWarehouse.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              '⚠️ Material Transfer requiere almacén origen y destino'),
          backgroundColor: AppDesign.orangeIcon,
        ),
      );
      return;
    }
    if (_selectedEntryType == 'Material Receipt' &&
        _selectedTargetWarehouse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('⚠️ Material Receipt requiere almacén destino'),
          backgroundColor: AppDesign.orangeIcon,
        ),
      );
      return;
    }
    if (_selectedEntryType == 'Material Issue' &&
        _selectedSourceWarehouse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('⚠️ Material Issue requiere almacén origen'),
          backgroundColor: AppDesign.orangeIcon,
        ),
      );
      return;
    }

    final provider = context.read<StockEntryProvider>();
    final namingSeries = _selectedNamingSeries.isNotEmpty
        ? _selectedNamingSeries
        : (provider.namingSeriesOptions.isNotEmpty
            ? provider.namingSeriesOptions.first
            : '');

    provider.createNewEntry(
      stockEntryType: _selectedEntryType,
      sourceWarehouse: _selectedSourceWarehouse,
      targetWarehouse: _selectedTargetWarehouse,
      costCenter: _selectedCostCenter,
      remarks: _remarksController.text.trim(),
      namingSeries: namingSeries,
      postingDate: _selectedDate,
    );
    setState(() => _showForm = false);
  }

  Future<void> _saveEntry() async {
    final provider = context.read<StockEntryProvider>();
    // Sincronizar las observaciones escritas antes de guardar
    provider.updateRemarks(_remarksController.text.trim());
    final ok = await provider.saveEntry();

    if (!mounted) return;

    if (ok) {
      // El provider ya refrescó la entrada desde el ERP
      setState(() {});
      _syncRateControllers(provider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '💾 Borrador guardado: ${provider.currentEntry?.id ?? ''}',
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

  Future<void> _submitEntry() async {
    final provider = context.read<StockEntryProvider>();

    if (!provider.isSaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Primero guardá la entrada como borrador'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar entrada'),
        content: const Text(
          '¿Confirmás que querés enviar esta entrada de inventario a ERPNext? Se moverá el stock y no podrá modificarse después.',
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

    final ok = await provider.submitEntry();

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('✅ Entrada ${provider.currentEntry?.id ?? ''} enviada'),
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
    final provider = context.watch<StockEntryProvider>();
    final entry = provider.currentEntry;

    // Tras guardar/refrescar, sincronizar los precios reales del ERP en los
    // controllers (sin pisar el campo que el usuario esté editando).
    if (entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncRateControllers(provider);
        _cleanupRateControllers(entry.items);
      });
    }

    return Scaffold(
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── Header navy ───
          AppDesign.buildHeader(
            title: entry?.id != null ? '📦 ${entry!.id}' : '📦 Nueva Entrada',
            subtitle: provider.isSubmitted
                ? 'Entrada enviada a ERPNext'
                : entry?.id != null
                    ? 'Entrada en borrador'
                    : 'Crear nueva entrada de inventario',
            icon: Icons.swap_horiz,
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
              if (entry?.id != null && !provider.isSubmitted)
                GestureDetector(
                  onTap: () => provider.loadEntry(entry!.id!),
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
            child: provider.loadingEntry
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Cargando datos...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  )
                : _showForm && entry == null
                    ? _buildCreationForm()
                    : _buildEntryDetail(),
          ),
        ],
      ),
    );
  }

  /// Formulario de creación de la entrada.
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
                  icon: Icons.swap_horiz,
                  bgColor: AppDesign.tealLight,
                  iconColor: AppDesign.tealIcon,
                  size: 56,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Registrar Entrada de Inventario',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppDesign.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Movimiento de stock — el costo lo calcula el ERP',
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

          // ─── Serie de Numeración (primero, como la Recepción) ───
          _buildSectionLabel('SERIE DE NUMERACIÓN'),
          const SizedBox(height: 6),
          Consumer<StockEntryProvider>(
            builder: (context, seProvider, _) {
              final series = seProvider.namingSeriesOptions;
              final loaded = seProvider.catalogsLoaded;
              if (!loaded) {
                return _buildDropdownField(
                  label: 'Serie de Numeración',
                  icon: Icons.tag,
                  hint: 'Cargando...',
                  items: const [],
                  value: null,
                  enabled: false,
                );
              }
              if (series.isEmpty) {
                return _buildDropdownField(
                  label: 'Serie de Numeración',
                  icon: Icons.tag,
                  hint: 'Default del ERP',
                  items: const [],
                  value: null,
                  enabled: false,
                );
              }
              final currentVal = (series.contains(_selectedNamingSeries))
                  ? _selectedNamingSeries
                  : series.first;
              return _buildDropdownField(
                label: 'Serie de Numeración',
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

          // ─── Tipo de Entrada de Stock (traído del ERP) ───
          _buildSectionLabel('TIPO DE ENTRADA DE STOCK'),
          const SizedBox(height: 6),
          Consumer<StockEntryProvider>(
            builder: (context, seProvider, _) {
              final types = seProvider.stockEntryTypes;
              final loaded = seProvider.catalogsLoaded;
              if (!loaded) {
                return _buildDropdownField(
                  label: 'Tipo de Entrada *',
                  icon: Icons.category,
                  hint: 'Cargando...',
                  items: const [],
                  value: null,
                  enabled: false,
                );
              }
              if (types.isEmpty) {
                return _buildDropdownField(
                  label: 'Tipo de Entrada *',
                  icon: Icons.category,
                  hint: 'No hay tipos disponibles',
                  items: const [],
                  value: null,
                  enabled: false,
                );
              }
              return _buildDropdownField(
                label: 'Tipo de Entrada *',
                icon: Icons.category,
                hint: 'Seleccionar tipo',
                items: types
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                value: _selectedEntryType.isNotEmpty ? _selectedEntryType : null,
                onChanged: (val) =>
                    setState(() => _selectedEntryType = val ?? ''),
              );
            },
          ),

          const SizedBox(height: 16),

          // ─── Centro de Costos ───
          _buildSectionLabel('CENTRO DE COSTOS'),
          const SizedBox(height: 6),
          Consumer<StockEntryProvider>(
            builder: (context, seProvider, _) {
              final centers = seProvider.costCenters;
              final loaded = seProvider.catalogsLoaded;
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

          // ─── Almacén Origen (solo si el tipo lo usa, como el ERP) ───
          if (_selectedEntryType == 'Material Transfer' ||
              _selectedEntryType == 'Material Issue') ...[
            _buildSectionLabel('ALMACÉN ORIGEN'),
            const SizedBox(height: 6),
            Consumer<StockEntryProvider>(
              builder: (context, seProvider, _) {
                final warehouses = seProvider.warehouses;
                final loaded = seProvider.catalogsLoaded;
                return _buildDropdownField(
                  label: 'Almacén Origen *',
                  icon: Icons.unarchive_outlined,
                  hint: !loaded ? 'Cargando...' : 'Seleccionar origen',
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
                  value: _selectedSourceWarehouse.isNotEmpty
                      ? _selectedSourceWarehouse
                      : null,
                  onChanged: (val) =>
                      setState(() => _selectedSourceWarehouse = val ?? ''),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // ─── Almacén Destino (solo si el tipo lo usa, como el ERP) ───
          if (_selectedEntryType == 'Material Transfer' ||
              _selectedEntryType == 'Material Receipt') ...[
            _buildSectionLabel('ALMACÉN DESTINO'),
            const SizedBox(height: 6),
            Consumer<StockEntryProvider>(
              builder: (context, seProvider, _) {
                final warehouses = seProvider.warehouses;
                final loaded = seProvider.catalogsLoaded;
                return _buildDropdownField(
                  label: 'Almacén Destino *',
                  icon: Icons.archive_outlined,
                  hint: !loaded ? 'Cargando...' : 'Seleccionar destino',
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
                  value: _selectedTargetWarehouse.isNotEmpty
                      ? _selectedTargetWarehouse
                      : null,
                  onChanged: (val) =>
                      setState(() => _selectedTargetWarehouse = val ?? ''),
                );
              },
            ),
            const SizedBox(height: 16),
          ],

          // ─── Fecha ───
          _buildSectionLabel('FECHA'),
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
                  labelText: 'Fecha *',
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

          // ─── Observaciones ───
          _buildSectionLabel('OBSERVACIONES'),
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
              controller: _remarksController,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Observaciones',
                hintText: 'Notas del movimiento (opcional)',
                prefixIcon:
                    const Icon(Icons.notes, color: AppDesign.navy),
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

  /// Detalle de entrada con escáner.
  Widget _buildEntryDetail() {
    final provider = context.watch<StockEntryProvider>();
    final inventoryProvider = context.watch<InventoryProvider>();
    final entry = provider.currentEntry;

    if (entry == null) {
      return AppDesign.emptyState(
        icon: Icons.error_outline,
        title: 'Entrada no disponible',
      );
    }

    final currency = inventoryProvider.companyCurrency;

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
                        final qty = parseFlexibleNumber(_qtyController.text) ??
                            1.0;
                        await provider.addItemToEntryByCode(
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

        // ─── CONTENIDO SCROLLABLE ───
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

                // ─── INFO ENTRADA (tipo + almacenes) ───
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppDesign.circleAvatar(
                            icon: Icons.category,
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
                                  'Tipo de entrada',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey[500],
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  entry.stockEntryType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: AppDesign.navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (entry.costCenter.isNotEmpty)
                            AppDesign.statusBadge(
                              entry.costCenter,
                              AppDesign.blueIcon,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (entry.sourceWarehouse.isNotEmpty) ...[
                            Icon(Icons.unarchive_outlined,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Origen: ${_shortWarehouse(entry.sourceWarehouse)}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          if (entry.targetWarehouse.isNotEmpty) ...[
                            Icon(Icons.archive_outlined,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Destino: ${_shortWarehouse(entry.targetWarehouse)}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
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
                        'ITEMS (${entry.items.length})',
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
                if (entry.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AppDesign.emptyState(
                      icon: Icons.qr_code_scanner,
                      title: 'Escaneá productos para agregar',
                      subtitle:
                          'Usá la cámara, escribí el código o buscá por nombre',
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: entry.items.length,
                    itemBuilder: (context, index) {
                      return _buildItemCard(entry.items[index], index);
                    },
                  ),

                // ─── RESUMEN ───
                // Material Receipt: gran total en moneda (Σ qty × precio
                // base). Transfer/Issue: solo conteo de unidades (el costo
                // lo pone el ERP).
                if (entry.items.isNotEmpty)
                  entry.stockEntryType == 'Material Receipt'
                      ? buildTotalsSummary(
                          subtotal: entry.subtotal,
                          tax: null,
                          total: entry.subtotal,
                          currency: currency,
                          qtyOnly: false,
                          hideTaxRow: true,
                          totalLabel: 'GRAN TOTAL',
                        )
                      : buildTotalsSummary(
                          subtotal: entry.totalQty,
                          tax: null,
                          total: null,
                          currency: '',
                          qtyOnly: true,
                        ),
              ],
            ),
          ),
        ),

        // ─── BOTÓN GUARDAR / ENVIAR ───
        if (entry.items.isNotEmpty && !provider.isSubmitted)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: provider.isLoading ? null : _saveEntry,
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
                            : _submitEntry,
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

  /// Acorta el nombre del almacén (quita la parte de la company si viene).
  String _shortWarehouse(String wh) {
    final parts = wh.split(' - ');
    return parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' - ') : wh;
  }

  /// Paso de los botones +/-: 0.5 si la UOM admite decimales, 1 si no.
  double _seStep(StockEntryProvider provider, StockEntryItem item) {
    return provider.erpNextService.uomAllowsDecimals(_uomOf(provider, item))
        ? 0.5
        : 1.0;
  }

  /// UOM del item (del item mismo o resuelta desde la caché).
  String _uomOf(StockEntryProvider provider, StockEntryItem item) {
    if (item.uom.isNotEmpty) return item.uom;
    final cached = provider.itemsByCode[item.itemCode.toUpperCase()];
    return cached?.stockUom ?? '';
  }

  Widget _buildItemCard(StockEntryItem item, int index) {
    final provider = context.read<StockEntryProvider>();
    final readOnly = provider.isSubmitted;

    // Moneda de la company (para el precio base de Material Receipt)
    final inventoryProvider = context.read<InventoryProvider>();
    final currency = inventoryProvider.companyCurrency;

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
                            index, item.qty - _seStep(provider, item)),
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
                            index, item.qty + _seStep(provider, item)),
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

            // Fila de UOM + precio base (solo Material Receipt) + almacenes
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppDesign.blueLight.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (item.uom.isNotEmpty) ...[
                    Text(
                      item.uom,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Precio base editable — solo en Material Receipt (en
                  // Transfer/Issue el costo lo pone el ERP y no se muestra).
                  if (!readOnly &&
                      provider.currentEntry?.stockEntryType ==
                          'Material Receipt') ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRECIO BASE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[600],
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(
                          width: 110,
                          child: TextField(
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
                              prefixText: currency.isNotEmpty ? '$currency ' : null,
                              prefixStyle: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
                            ),
                            controller: _getRateController(
                                item.itemCode, item.basicRate),
                            onChanged: (val) {
                              final parsed =
                                  parseFlexibleNumber(val) ?? 0.0;
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
                        ),
                      ],
                    ),
                    const Spacer(),
                  ] else ...[
                    const Spacer(),
                  ],
                  Expanded(
                    child: Text(
                      item.sourceWarehouse.isNotEmpty &&
                              item.targetWarehouse.isNotEmpty
                          ? '${_shortWarehouse(item.sourceWarehouse)} → ${_shortWarehouse(item.targetWarehouse)}'
                          : (item.sourceWarehouse.isNotEmpty
                              ? 'Origen: ${_shortWarehouse(item.sourceWarehouse)}'
                              : (item.targetWarehouse.isNotEmpty
                                  ? 'Destino: ${_shortWarehouse(item.targetWarehouse)}'
                                  : '')),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
