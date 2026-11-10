import 'dart:convert';
import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/label_template.dart';
import '../providers/label_provider.dart';
import '../theme/app_design.dart';

/// Diseñador de etiquetas: arrastrá y estirá los campos (nombre, precio,
/// código de barras, número y logo) sobre el lienzo de la etiqueta.
/// Se guarda como plantilla y la impresión la usa tal cual.
class LabelDesignerScreen extends StatefulWidget {
  const LabelDesignerScreen({super.key});

  @override
  State<LabelDesignerScreen> createState() => _LabelDesignerScreenState();
}

class _LabelDesignerScreenState extends State<LabelDesignerScreen> {
  late List<LabelField> _fields;
  int? _selected;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final lp = context.read<LabelProvider>();
    _fields = lp.effectiveTemplate.fields.map((f) => f.copy()).toList();
  }

  LabelField? get _sel =>
      _selected != null && _selected! < _fields.length ? _fields[_selected!] : null;

  void _touch() => _dirty = true;

  // ─── Agregar campos ───

  void _addField(String type) {
    final lp = context.read<LabelProvider>();
    final w = lp.settings.widthMm.toDouble();
    final h = lp.settings.heightMm.toDouble();
    setState(() {
      _fields.add(LabelField(
        type: type,
        x: w * 0.1,
        y: h * 0.35,
        w: w * 0.8,
        h: type == 'barcode' ? h * 0.25 : h * 0.18,
        fontMm: type == 'price' ? h * 0.28 : h * 0.14,
        bold: type == 'price' || type == 'name',
      ));
      _selected = _fields.length - 1;
      _touch();
    });
  }

  // ─── Guardar ───

  Future<void> _save() async {
    final lp = context.read<LabelProvider>();
    await lp.saveTemplate(LabelTemplate(fields: _fields), enable: true);
    if (!mounted) return;
    // Mensaje según si llegó al ERP (todos los dispositivos) o solo local.
    final msg = lp.templateSyncMessage ??
        '✅ Plantilla guardada — se usa al imprimir';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: msg.contains('falló') ? Colors.orange : Colors.green,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar plantilla'),
        content: const Text(
            '¿Volver al modelo por defecto (precio arriba-izquierda, logo '
            'arriba-derecha, nombre y código al pie)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restaurar')),
        ],
      ),
    );
    if (ok != true) return;
    final lp = context.read<LabelProvider>();
    await lp.resetTemplate();
    if (!mounted) return;
    setState(() {
      _fields = lp.effectiveTemplate.fields.map((f) => f.copy()).toList();
      _selected = null;
      _dirty = false;
    });
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final bg = AppDesign.bg;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('🎨 Diseñador de etiqueta'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Restaurar modelo por defecto',
            onPressed: _reset,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: 'Guardar plantilla',
            onPressed: _save,
            icon: const Icon(Icons.check_circle, color: Colors.green),
          ),
        ],
      ),
      body: Consumer<LabelProvider>(
        builder: (context, lp, _) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildCanvas(lp),
                ),
              ),
              _buildToolbar(lp),
            ],
          );
        },
      ),
    );
  }

  // ─── LIENZO ───

  Widget _buildCanvas(LabelProvider lp) {
    final wMm = lp.settings.widthMm.toDouble();
    final hMm = lp.settings.heightMm.toDouble();

    return LayoutBuilder(builder: (context, constraints) {
      final canvasW = constraints.maxWidth;
      final scale = canvasW / wMm;
      final canvasH = hMm * scale;

      return Center(
        child: Container(
          width: canvasW,
          height: canvasH,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppDesign.navy, width: 2),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < _fields.length; i++)
                _buildField(lp, i, scale),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildField(LabelProvider lp, int index, double scale) {
    final f = _fields[index];
    final wMm = lp.settings.widthMm.toDouble();
    final hMm = lp.settings.heightMm.toDouble();
    final selected = _selected == index;

    return Positioned(
      left: (f.x * scale).clamp(0.0, double.infinity),
      top: (f.y * scale).clamp(0.0, double.infinity),
      width: f.w * scale,
      height: f.h * scale,
      child: GestureDetector(
        onTap: () => setState(() => _selected = index),
        onPanUpdate: (d) {
          setState(() {
            f.x = (f.x + d.delta.dx / scale)
                .clamp(0.0, wMm - f.w)
                .toDouble();
            f.y = (f.y + d.delta.dy / scale)
                .clamp(0.0, hMm - f.h)
                .toDouble();
          });
          _touch();
        },
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? Colors.blue.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border.all(
              color: selected ? Colors.blue : Colors.grey.withValues(alpha: 0.5),
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: _buildFieldPreview(lp, f, scale),
              ),
              // Manija de redimensionar (esquina inferior derecha)
              Positioned(
                right: -8,
                bottom: -8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    setState(() {
                      f.w = (f.w + d.delta.dx / scale).clamp(3.0, wMm - f.x);
                      f.h = (f.h + d.delta.dy / scale)
                          .clamp(1.5, hMm - f.y);
                    });
                    _touch();
                  },
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: selected ? Colors.blue : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.open_in_full,
                        size: 10, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Vista previa del contenido del campo (a escala real de impresión).
  Widget _buildFieldPreview(LabelProvider lp, LabelField f, double scale) {
    switch (f.type) {
      case 'name':
        return _fieldText('Nombre del producto', f, scale, bold: true);
      case 'price':
        return _fieldText('L 25.00', f, scale, bold: true);
      case 'code':
        return _fieldText('7501234567890', f, scale, bold: false);
      case 'barcode':
        return CustomPaint(
          painter: _BarcodePreviewPainter(),
          size: Size.infinite,
        );
      case 'logo':
        return Padding(
          padding: const EdgeInsets.all(2),
          child: Image.asset(
            'assets/logo/superzito.png',
            fit: BoxFit.contain,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _fieldText(String text, LabelField f, double scale,
      {required bool bold}) {
    return Center(
      child: Text(
        text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: (f.fontMm * scale).clamp(5.0, 60.0),
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: Colors.black,
        ),
      ),
    );
  }

  // ─── TOOLBAR INFERIOR ───

  Widget _buildToolbar(LabelProvider lp) {
    final f = _sel;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: f == null ? _buildAddBar() : _buildFieldEditor(lp, f),
      ),
    );
  }

  Widget _buildAddBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text(
            'Agregar:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          _addChip('Nombre', Icons.abc, 'name'),
          _addChip('Precio', Icons.payments_outlined, 'price'),
          _addChip('Código de barras', Icons.qr_code_scanner, 'barcode'),
          _addChip('Nº código', Icons.tag, 'code'),
          _addChip('Logo', Icons.image_outlined, 'logo'),
        ],
      ),
    );
  }

  Widget _addChip(String label, IconData icon, String type) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onPressed: () => _addField(type),
      ),
    );
  }

  Widget _buildFieldEditor(LabelProvider lp, LabelField f) {
    final typeNames = {
      'name': 'Nombre',
      'price': 'Precio',
      'barcode': 'Código de barras',
      'code': 'Nº código',
      'logo': 'Logo',
    };
    final isText = f.type == 'name' || f.type == 'price' || f.type == 'code';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                typeNames[f.type] ?? f.type,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'x ${f.x.toStringAsFixed(1)} • y ${f.y.toStringAsFixed(1)} • '
              '${f.w.toStringAsFixed(1)}×${f.h.toStringAsFixed(1)} mm',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Quitar campo',
              onPressed: () {
                setState(() {
                  _fields.removeAt(_selected!);
                  _selected = null;
                  _touch();
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Deseleccionar',
              onPressed: () => setState(() => _selected = null),
            ),
          ],
        ),
        if (isText) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Tamaño texto:',
                  style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: f.fontMm.clamp(1.5, 12.0),
                  min: 1.5,
                  max: 12.0,
                  divisions: 21,
                  label: '${f.fontMm.toStringAsFixed(1)} mm',
                  onChanged: (v) {
                    setState(() => f.fontMm = v);
                    _touch();
                  },
                ),
              ),
              Checkbox(
                value: f.bold,
                onChanged: (v) {
                  setState(() => f.bold = v ?? false);
                  _touch();
                },
              ),
              const Text('Negrita', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
        if (f.type == 'barcode')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Las barras se imprimen como EAN-13/EAN-8 (o Code128 si el '
              'código no es EAN). Ajustá el alto estirando la caja.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
      ],
    );
  }
}

/// Pintor de vista previa del código de barras (barras EAN-13 de muestra).
class _BarcodePreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    // 12 dígitos: el paquete agrega el dígito verificador. Con 13 dígitos
    // y check digit inválido, makeBytes lanza BarcodeException y tumba el
    // lienzo entero.
    const code = '750123456789';
    try {
      final bars = bc.Barcode.ean13().makeBytes(
        Uint8List.fromList(utf8.encode(code)),
        width: size.width,
        height: size.height,
      );
      for (final bar in bars) {
        if (bar is bc.BarcodeBar && bar.black) {
          canvas.drawRect(
            Rect.fromLTWH(bar.left, bar.top, bar.width, bar.height),
            paint,
          );
        }
      }
    } catch (_) {
      // Nunca debe pasar con la muestra fija, pero el pintor no puede
      // tumbar la pantalla del diseñador jamás.
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
