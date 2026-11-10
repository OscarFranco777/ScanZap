import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/label_settings.dart';
import '../providers/inventory_provider.dart';
import '../providers/label_provider.dart';
import '../services/label_printer_service.dart';
import '../theme/app_design.dart';

/// Pantalla de configuración de la app.
/// Solo configuraciones — Permisos del usuario y Etiquetas de Precio.
/// El inicio de sesión vive aparte (pantalla /login desde el home).
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  bool _checkingPerms = false;
  List<Map<String, dynamic>> _permResults = [];
  String? _permError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<InventoryProvider>();
      // Si el login ya corrió la validación de permisos (auto-login con
      // Recordarme, o login manual previo), mostrar el resultado de una.
      if (provider.permissionResults.isNotEmpty &&
          _permResults.isEmpty) {
        setState(() => _permResults = provider.permissionResults);
      }
      _initLabelConfig();
    });
  }

  /// Carga la configuración del módulo de Etiquetas de Precio (vive acá
  /// junto al resto de la configuración de la app).
  Future<void> _initLabelConfig() async {
    try {
      final lp = context.read<LabelProvider>();
      await lp.loadSettings();
      await lp.loadTemplate();
      if (lp.priceLists.isEmpty) lp.loadPriceLists();
      // Sin promptEnable: abrir Configuración NO debe lanzar el diálogo
      // del sistema de encender Bluetooth (y el permiso runtime ya se
      // pide dentro de refreshBluetooth).
      await lp.refreshBluetooth();
    } catch (_) {
      // La configuración no debe tumbar la app por nada que falle acá.
    }
  }

  /// Valida que el usuario tenga acceso de lectura a los registros clave
  /// (centro de costo, almacén, plantillas de impuestos).
  Future<void> _validatePermissions() async {
    setState(() {
      _checkingPerms = true;
      _permResults = [];
      _permError = null;
    });

    final provider = context.read<InventoryProvider>();

    // Si no hay sesión activa, avisar en vez de marcar todo en rojo.
    try {
      await provider.erpNextService.testConnection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingPerms = false;
        _permError = 'Iniciá sesión primero para validar los permisos.';
      });
      return;
    }

    try {
      final results = await provider.erpNextService.checkUserPermissions();
      if (!mounted) return;
      setState(() => _permResults = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _permError = e.toString().replaceFirst('Exception: ', ''));
    }

    if (mounted) setState(() => _checkingPerms = false);
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppDesign.bg;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('⚙️ Configuración'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Permisos del usuario ───
          _buildPermisosCard(),
          const SizedBox(height: 16),

          // ─── Etiquetas de Precio ───
          _buildEtiquetasCard(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // PERMISOS DEL USUARIO
  // ══════════════════════════════════════════════════════════════

  Widget _buildPermisosCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 20, color: AppDesign.navy),
              SizedBox(width: 8),
              Text(
                'Permisos del usuario',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Verifica que tu usuario tenga acceso a los registros que el app '
            'necesita: centro de costo, almacén y plantillas de impuestos.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: _checkingPerms ? null : _validatePermissions,
              icon: _checkingPerms
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(_checkingPerms ? 'Validando...' : 'Validar permisos'),
            ),
          ),

          // Resultado de la validación
          if (_permError != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Text(
                _permError!,
                style: TextStyle(color: Colors.orange[900]),
              ),
            ),
          ],
          if (_permResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  for (final r in _permResults)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            r['ok'] == true ? Icons.check_circle : Icons.cancel,
                            color:
                                r['ok'] == true ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['label'] as String,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  r['ok'] == true
                                      ? 'Con acceso (leer y elegir)'
                                      : r['read'] == true
                                          ? 'Puede leer pero NO elegir (select) — pedile al administrador el rol necesario'
                                          : 'Sin acceso — pedile al administrador el rol necesario',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: r['ok'] == true
                                        ? Colors.green[700]
                                        : Colors.red[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_permResults.any((r) => r['ok'] != true))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '⚠️ Tu usuario no tiene acceso a algunos registros. '
                        'Pedile al administrador que te asigne los permisos '
                        'necesarios.',
                        style: TextStyle(fontSize: 12, color: Colors.red[800]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // ETIQUETAS DE PRECIO — configuración del módulo
  // ══════════════════════════════════════════════════════════════

  Widget _buildEtiquetasCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.all(16),
      child: Consumer<LabelProvider>(
        builder: (context, lp, _) {
          final s = lp.settings;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.label_outline,
                      size: 20, color: AppDesign.navy),
                  SizedBox(width: 8),
                  Text(
                    'Etiquetas de Precio',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Impresora Bluetooth, lista de precios y tipo de etiqueta '
                'que usa el módulo de Etiquetas.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),

              if (!lp.printerService.isSupported)
                _labelInfo(
                  '⚠️ La impresión Bluetooth solo funciona en Android.',
                )
              else ...[
                // ─── Impresora BT ───
                _buildLabelPrinterField(lp),
                const SizedBox(height: 12),
              ],

              // ─── Lista de precios ───
              _buildLabelPriceListField(lp),
              const SizedBox(height: 12),

              // ─── Tipo de etiqueta ───
              DropdownButtonFormField<String>(
                initialValue: s.paperType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de etiqueta',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'continuous',
                    child: Text('Continuo (rollo de recibo)'),
                  ),
                  DropdownMenuItem(
                    value: 'gap',
                    child: Text('Troquelada con separación (gap)'),
                  ),
                  DropdownMenuItem(
                    value: 'blackmark',
                    child: Text('Marca negra'),
                  ),
                ],
                onChanged: (v) => _saveLabelSettings(lp, paperType: v),
              ),
              const SizedBox(height: 12),

              // ─── Tamaño ───
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: s.widthMm,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Ancho papel (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [20, 30, 40, 50, 58, 76, 80]
                          .map((w) => DropdownMenuItem<int>(
                                value: w,
                                child: Text('$w mm'),
                              ))
                          .toList(),
                      onChanged: (v) => _saveLabelSettings(lp, widthMm: v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: s.heightMm.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Alto (mm)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final h = int.tryParse(v);
                        if (h != null && h >= 10 && h <= 300) {
                          _saveLabelSettings(lp, heightMm: h);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ─── Lenguaje ───
              DropdownButtonFormField<String>(
                initialValue: s.printerType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Lenguaje de impresora',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'escpos',
                    child: Text('ESC/POS (3nStar, TSC continuo)'),
                  ),
                  DropdownMenuItem(
                    value: 'tsc',
                    child: Text('TSPL2 (TSC troquelada/marca)'),
                  ),
                ],
                onChanged: (v) => _saveLabelSettings(lp, printerType: v),
              ),
              const SizedBox(height: 4),
              _labelInfo(
                'Con etiqueta troquelada o marca negra siempre se usa TSPL2 '
                'aunque el lenguaje esté en ESC/POS.',
              ),

              const Divider(height: 24),

              // ─── Diseñador de etiquetas ───
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Plantilla de etiqueta',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          s.useTemplate
                              ? 'Activa — se imprime según tu diseño'
                              : 'Inactiva — layout fijo',
                          style: TextStyle(
                            fontSize: 11,
                            color: s.useTemplate
                                ? Colors.green[700]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: s.useTemplate,
                    onChanged: (v) => lp.setUseTemplate(v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/label-designer'),
                  icon: const Icon(Icons.design_services_outlined),
                  label: const Text(
                    '🎨 Diseñar etiqueta',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _labelInfo(
                'En el diseñador arrastrás y estirá los campos: nombre, '
                'precio, código de barras, número y logo.',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLabelPrinterField(LabelProvider lp) {
    if (lp.btLoading) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (!lp.btEnabled) {
      return _labelInfo(
        '⚠️ Bluetooth apagado o sin permiso. Tocá refrescar: la app pedirá '
        'el permiso de Bluetooth y/o encenderlo.',
      );
    }
    final macs = lp.btDevices.map((d) => d.address).toSet().toList();
    final currentMac = lp.settings.printerMac;
    // Si la guardada no está entre las emparejadas, agregarla para no perderla
    if (currentMac.isNotEmpty && !macs.contains(currentMac)) {
      macs.add(currentMac);
    }
    if (macs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _labelInfo(
            'No hay impresoras emparejadas. Emparejá la impresora en '
            'Ajustes → Bluetooth y tocá refrescar.',
          ),
          TextButton.icon(
            onPressed: () => lp.refreshBluetooth(promptEnable: true),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refrescar'),
          ),
        ],
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: macs.contains(currentMac) ? currentMac : null,
      isExpanded: true,
      hint: const Text('Elegí la impresora'),
      decoration: InputDecoration(
        labelText: 'Impresora Bluetooth',
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: () => lp.refreshBluetooth(promptEnable: true),
        ),
      ),
      items: macs.map((mac) {
        final dev = lp.deviceByMac(mac) ??
            BtDevice(name: lp.settings.printerName, address: mac);
        return DropdownMenuItem<String>(value: mac, child: Text(dev.name));
      }).toList(),
      onChanged: (mac) {
        if (mac == null) return;
        final dev = lp.deviceByMac(mac) ??
            BtDevice(name: 'Impresora', address: mac);
        _saveLabelSettings(lp, printerMac: mac, printerName: dev.name);
      },
    );
  }

  Widget _buildLabelPriceListField(LabelProvider lp) {
    if (lp.loadingPriceLists) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (lp.priceLists.isEmpty) {
      return _labelInfo(
        'No se pudieron cargar las listas de precios — iniciá sesión para '
        'cargarlas.',
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: lp.priceLists.contains(lp.settings.priceList)
          ? lp.settings.priceList
          : null,
      isExpanded: true,
      hint: const Text('Elegí la lista de precios'),
      decoration: const InputDecoration(
        labelText: 'Lista de precios por defecto',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: lp.priceLists
          .map((pl) => DropdownMenuItem<String>(value: pl, child: Text(pl)))
          .toList(),
      onChanged: (v) => _saveLabelSettings(lp, priceList: v),
    );
  }

  Widget _labelInfo(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
      ),
    );
  }

  Future<void> _saveLabelSettings(
    LabelProvider lp, {
    String? priceList,
    String? printerType,
    String? paperType,
    int? widthMm,
    int? heightMm,
    String? printerMac,
    String? printerName,
  }) async {
    final s = lp.settings;
    await lp.updateSettings(LabelSettings(
      priceList: priceList ?? s.priceList,
      printerType: printerType ?? s.printerType,
      paperType: paperType ?? s.paperType,
      widthMm: widthMm ?? s.widthMm,
      heightMm: heightMm ?? s.heightMm,
      printerMac: printerMac ?? s.printerMac,
      printerName: printerName ?? s.printerName,
      copies: s.copies,
      useTemplate: s.useTemplate,
    ));
  }
}
