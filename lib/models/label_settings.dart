import 'package:shared_preferences/shared_preferences.dart';

/// Configuración del módulo de Etiquetas de Precio.
/// Todo persiste en SharedPreferences para sobrevivir reinicios.
class LabelSettings {
  /// Lista de precios de ERPNext desde la que se toman los precios.
  String priceList;

  /// Tipo de impresora / lenguaje de comandos:
  ///  - 'escpos': ESC/POS (base común — 3nStar y TSC en modo recibo)
  ///  - 'tsc':    TSPL2 (TSC Alpha-3RB con etiquetas troqueladas/marca negra)
  String printerType;

  /// Tipo de papel:
  ///  - 'continuous': rollo continuo (recibo)
  ///  - 'gap':        etiquetas troqueladas con separación (gap)
  ///  - 'blackmark':  papel con marca negra trasera
  String paperType;

  /// Ancho del papel en mm (58 u 80 típicamente).
  int widthMm;

  /// Alto de la etiqueta en mm (solo aplica a gap/blackmark).
  int heightMm;

  /// Impresora Bluetooth emparejada por defecto.
  String printerMac;
  String printerName;

  /// Copias por defecto al imprimir una etiqueta.
  int copies;

  /// Usar la plantilla diseñada (posiciones/sizes de campos) en vez del
  /// layout fijo. La plantilla vive en LabelTemplate (JSON en prefs).
  bool useTemplate;

  LabelSettings({
    this.priceList = '',
    this.printerType = 'escpos',
    this.paperType = 'continuous',
    this.widthMm = 80,
    this.heightMm = 25,
    this.printerMac = '',
    this.printerName = '',
    this.copies = 1,
    this.useTemplate = false,
  });

  /// Copia con todos los valores de otra configuración.
  LabelSettings.from(LabelSettings other)
      : priceList = other.priceList,
        printerType = other.printerType,
        paperType = other.paperType,
        widthMm = other.widthMm,
        heightMm = other.heightMm,
        printerMac = other.printerMac,
        printerName = other.printerName,
        copies = other.copies,
        useTemplate = other.useTemplate;

  bool get isConfigured => priceList.isNotEmpty && printerMac.isNotEmpty;

  /// Etiquetas troqueladas o con marca requieren driver TSPL2 para
  /// que el sensor posicione bien cada etiqueta.
  bool get needsTspl2 => paperType != 'continuous';

  // ─── Persistencia ───
  static const _kPriceList = 'label_price_list';
  static const _kPrinterType = 'label_printer_type';
  static const _kPaperType = 'label_paper_type';
  static const _kWidthMm = 'label_width_mm';
  static const _kHeightMm = 'label_height_mm';
  static const _kPrinterMac = 'label_printer_mac';
  static const _kPrinterName = 'label_printer_name';
  static const _kCopies = 'label_copies';
  static const _kUseTemplate = 'label_use_template';

  static Future<LabelSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = LabelSettings(
      priceList: prefs.getString(_kPriceList) ?? '',
      printerType: prefs.getString(_kPrinterType) ?? 'escpos',
      paperType: prefs.getString(_kPaperType) ?? 'continuous',
      widthMm: prefs.getInt(_kWidthMm) ?? 80,
      heightMm: prefs.getInt(_kHeightMm) ?? 25,
      printerMac: prefs.getString(_kPrinterMac) ?? '',
      printerName: prefs.getString(_kPrinterName) ?? '',
      copies: prefs.getInt(_kCopies) ?? 1,
      useTemplate: prefs.getBool(_kUseTemplate) ?? false,
    );
    if (s.copies < 1) s.copies = 1;
    if (s.widthMm < 20) s.widthMm = 80;
    if (s.heightMm < 10) s.heightMm = 25;
    return s;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPriceList, priceList);
    await prefs.setString(_kPrinterType, printerType);
    await prefs.setString(_kPaperType, paperType);
    await prefs.setInt(_kWidthMm, widthMm);
    await prefs.setInt(_kHeightMm, heightMm);
    await prefs.setString(_kPrinterMac, printerMac);
    await prefs.setString(_kPrinterName, printerName);
    await prefs.setInt(_kCopies, copies);
    await prefs.setBool(_kUseTemplate, useTemplate);
  }
}
