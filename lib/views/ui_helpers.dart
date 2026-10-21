import 'dart:async';
import 'package:flutter/material.dart';
import '../services/erpnext_service.dart';
import '../theme/app_design.dart';

/// Formatea una cantidad: 2.0 → "2", 1.5 → "1.5" (sin ceros de más).
String fmtQty(num q) {
  if (q == q.roundToDouble()) return q.round().toString();
  return q.toString();
}

/// Diálogo para editar la cantidad exacta de un item.
/// Si [allowsDecimals] es false, valida que la cantidad sea entera.
Future<double?> showQtyInputDialog(
  BuildContext context, {
  required double current,
  required bool allowsDecimals,
  String? uom,
}) {
  final controller = TextEditingController(text: fmtQty(current));
  String? errorText;
  return showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text('Cantidad${(uom ?? '').isNotEmpty ? ' ($uom)' : ''}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: allowsDecimals ? 'Cantidad (admite decimales)' : 'Cantidad (solo enteros)',
            errorText: errorText,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              if (parsed == null || parsed < 0) {
                setDialogState(() => errorText = 'Cantidad inválida');
                return;
              }
              if (!allowsDecimals && parsed != parsed.roundToDouble()) {
                setDialogState(() => errorText =
                    'Este producto no admite decimales (UOM: ${uom ?? ''})');
                return;
              }
              Navigator.of(ctx).pop(parsed == 0 ? null : parsed);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    ),
  );
}

/// Tarjeta de resumen de totales: Subtotal / Impuesto / Total.
/// Si [tax] o [total] son null (documento aún no guardado en el ERP),
/// muestra "—" y aclara que los impuestos los calcula el ERP al guardar.
Widget buildTotalsSummary({
  required double subtotal,
  double? tax,
  double? total,
  String currency = '',
}) {
  // Símbolo si lo conocemos; si no, el código de la moneda (ej: HNL).
  String cur = currency;
  if (cur == 'HNL') {
    cur = 'L';
  } else if (cur == 'USD') {
    cur = '\$';
  }
  String money(double v) => cur.isEmpty
      ? v.toStringAsFixed(2)
      : '$cur ${v.toStringAsFixed(2)}';

  Widget totalsRow(String label, String value,
      {double fontSize = 13,
      FontWeight weight = FontWeight.w600,
      Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: weight,
              color: color ?? AppDesign.navy,
            ),
          ),
        ],
      ),
    );
  }

  final missingTax = tax == null || total == null;

  return Container(
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppDesign.tealLight.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppDesign.tealIcon.withValues(alpha: 0.3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long, size: 14, color: AppDesign.tealIcon),
            const SizedBox(width: 6),
            Text(
              'RESUMEN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppDesign.tealIcon,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        totalsRow('Subtotal', money(subtotal)),
        totalsRow('Impuesto', tax != null ? money(tax) : '—'),
        Divider(
          height: 12,
          thickness: 1,
          color: AppDesign.tealIcon.withValues(alpha: 0.3),
        ),
        totalsRow('Total', total != null ? money(total) : '—',
            fontSize: 16, weight: FontWeight.w800),
        if (missingTax)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Los impuestos los calcula el ERP al guardar el documento',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: Colors.grey[500],
              ),
            ),
          ),
      ],
    ),
  );
}

/// Diálogo de búsqueda escrita de items (por código o nombre).
/// Devuelve la fila del item elegido (name, item_code, item_name, stock_uom)
/// o null si se cerró sin elegir.
Future<Map<String, dynamic>?> showItemSearchDialog(
  BuildContext context,
  ErpNextService service, {
  String title = 'Buscar producto',
}) {
  final searchCtrl = TextEditingController();
  Timer? debounce;
  List<Map<String, dynamic>> results = [];
  bool searching = false;
  String error = '';

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.search, size: 22, color: AppDesign.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Código o nombre',
                  hintText: 'Ej: libra, queso, AB-001...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: searching
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
                onChanged: (v) {
                  debounce?.cancel();
                  debounce = Timer(const Duration(milliseconds: 400), () async {
                    final q = v.trim();
                    if (q.length < 2) {
                      setDialogState(() {
                        results = [];
                        error = '';
                      });
                      return;
                    }
                    setDialogState(() => searching = true);
                    final found = await service.searchItems(q);
                    if (!ctx.mounted) return;
                    setDialogState(() {
                      searching = false;
                      results = found;
                      error = found.isEmpty
                          ? 'Sin resultados para "$q"'
                          : '';
                    });
                  });
                },
              ),
              const SizedBox(height: 8),
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (ctx2, i) {
                    final row = results[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.inventory_2_outlined,
                          size: 20, color: AppDesign.tealIcon),
                      title: Text(
                        (row['item_name'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${row['item_code']} — ${row['stock_uom'] ?? ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => Navigator.of(ctx).pop(row),
                    );
                  },
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
        ],
      ),
    ),
  );
}
