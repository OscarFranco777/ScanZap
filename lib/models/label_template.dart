import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Un campo dentro de la plantilla de etiqueta.
///
/// Todas las medidas están en milímetros, sobre una etiqueta de
/// [LabelSettings.widthMm] × [LabelSettings.heightMm].
///
/// Tipos de campo:
///  - 'name'    : nombre del producto
///  - 'price'   : precio formateado (ej. "L 25.00")
///  - 'barcode' : barras del código de barras (EAN-13/8 o Code128)
///  - 'code'    : número del código de barras (texto)
///  - 'logo'    : logo SuperZito (asset de la app)
class LabelField {
  String type;

  /// Posición y tamaño en mm dentro de la etiqueta.
  double x;
  double y;
  double w;
  double h;

  /// Altura del texto en mm (solo campos de texto).
  double fontMm;

  /// Texto en negrita (solo campos de texto).
  bool bold;

  LabelField({
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.fontMm = 3,
    this.bold = false,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'fontMm': fontMm,
        'bold': bold,
      };

  factory LabelField.fromJson(Map<String, dynamic> j) => LabelField(
        type: (j['type'] ?? 'name') as String,
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        w: (j['w'] as num?)?.toDouble() ?? 20,
        h: (j['h'] as num?)?.toDouble() ?? 4,
        fontMm: (j['fontMm'] as num?)?.toDouble() ?? 3,
        bold: (j['bold'] ?? false) as bool,
      );

  LabelField copy() => LabelField(
        type: type,
        x: x,
        y: y,
        w: w,
        h: h,
        fontMm: fontMm,
        bold: bold,
      );
}

/// Plantilla de etiqueta: la lista de campos con su posición y tamaño.
/// Se persiste como JSON en SharedPreferences junto al resto de la
/// configuración del módulo de Etiquetas de Precio.
class LabelTemplate {
  List<LabelField> fields;

  LabelTemplate({required this.fields});

  Map<String, dynamic> toJson() => {
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  factory LabelTemplate.fromJson(Map<String, dynamic> j) => LabelTemplate(
        fields: ((j['fields'] ?? []) as List)
            .map((e) => LabelField.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Plantilla por defecto: el modelo del cliente — precio grande arriba a
  /// la izquierda, logo arriba a la derecha, nombre del producto debajo y
  /// el código de barras con su número al pie. Se genera según el tamaño
  /// de etiqueta configurado.
  factory LabelTemplate.defaultTemplate({required int widthMm, required int heightMm}) {
    final w = widthMm.toDouble();
    final h = heightMm.toDouble();
    return LabelTemplate(fields: [
      // Precio grande arriba-izquierda
      LabelField(
        type: 'price',
        x: 2,
        y: 1.5,
        w: w * 0.55,
        h: h * 0.34,
        fontMm: h * 0.30,
        bold: true,
      ),
      // Logo arriba-derecha
      LabelField(
        type: 'logo',
        x: w * 0.62,
        y: 1.5,
        w: w * 0.34,
        h: h * 0.30,
      ),
      // Nombre del producto debajo
      LabelField(
        type: 'name',
        x: 2,
        y: h * 0.40,
        w: w - 4,
        h: h * 0.22,
        fontMm: h * 0.16,
        bold: true,
      ),
      // Código de barras
      LabelField(
        type: 'barcode',
        x: w * 0.10,
        y: h * 0.64,
        w: w * 0.80,
        h: h * 0.24,
      ),
      // Número del código al pie
      LabelField(
        type: 'code',
        x: 2,
        y: h - 3,
        w: w - 4,
        h: 2.5,
        fontMm: 2.2,
      ),
    ]);
  }

  // ─── Persistencia (el JSON vive en SharedPreferences; el flag
  // useTemplate y el guardado se manejan desde LabelSettings) ───
  static Future<LabelTemplate?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kJsonKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return LabelTemplate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static const kJsonKey = 'label_template_json';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kJsonKey, jsonEncode(toJson()));
  }
}
