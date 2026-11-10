import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:image/image.dart' as img;

import '../models/label_settings.dart';
import '../models/label_template.dart';
import 'label_raster.dart';

/// Datos de una etiqueta a imprimir.
class LabelData {
  final String itemName;
  final String itemCode;

  /// Código a codificar como barcode (uno de los códigos de barras del item).
  final String barcode;

  /// Precio ya formateado para imprimir (ej. "L 45.00").
  final String priceText;
  final String uom;

  LabelData({
    required this.itemName,
    required this.itemCode,
    required this.barcode,
    required this.priceText,
    required this.uom,
  });
}

/// Dispositivo Bluetooth emparejado (para el selector de la UI).
class BtDevice {
  final String name;
  final String address;
  BtDevice({required this.name, required this.address});
}

/// Servicio de impresión de etiquetas por Bluetooth.
///
/// Soporta:
///  - ESC/POS (base común: 3nStar PPT305BT/PPT205BT y TSC en modo recibo)
///  - TSPL2   (TSC Alpha-3RB con etiquetas troqueladas con gap o marca negra)
class LabelPrinterService {
  BluetoothConnection? _connection;
  String? _connectedMac;

  /// Bluetooth disponible en este dispositivo (solo Android).
  bool get isSupported => Platform.isAndroid;

  Future<bool> get isBluetoothEnabled async {
    if (!isSupported) return false;
    try {
      final state = await FlutterBluetoothSerial.instance.state;
      return state == BluetoothState.STATE_ON;
    } catch (_) {
      return false;
    }
  }

  /// Pide activar el Bluetooth (diálogo del sistema).
  Future<bool> requestEnable() async {
    if (!isSupported) return false;
    try {
      await FlutterBluetoothSerial.instance.requestEnable();
      return await isBluetoothEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Lista los dispositivos ya emparejados.
  Future<List<BtDevice>> listBondedDevices() async {
    if (!isSupported) return [];
    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      return devices
          .map((d) => BtDevice(name: d.name ?? d.address, address: d.address))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      return [];
    }
  }

  /// Conecta a la impresora por Bluetooth (SPP). Reutiliza la conexión viva.
  Future<bool> connect(String mac) async {
    if (!isSupported) return false;
    if (_connectedMac == mac &&
        _connection != null &&
        _connection!.isConnected) {
      return true;
    }
    await disconnect();
    try {
      _connection = await BluetoothConnection.toAddress(mac).timeout(
        const Duration(seconds: 8),
      );
      _connectedMac = mac;
      return _connection!.isConnected;
    } catch (_) {
      _connection = null;
      _connectedMac = null;
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _connection?.finish();
    } catch (_) {}
    _connection = null;
    _connectedMac = null;
  }

  /// Imprime [copies] copias de la etiqueta según la configuración.
  /// Lanza Exception con mensaje amigable si algo falla.
  Future<void> printLabel({
    required LabelData label,
    required LabelSettings settings,
    int? copies,
  }) async {
    if (!isSupported) {
      throw Exception(
        'La impresión Bluetooth solo está disponible en Android.',
      );
    }
    if (settings.printerMac.isEmpty) {
      throw Exception('Seleccioná una impresora Bluetooth primero.');
    }

    var n = copies ?? settings.copies;
    if (n < 1) n = 1;

    final ok = await connect(settings.printerMac);
    if (!ok) {
      throw Exception(
        'No se pudo conectar a la impresora "${settings.printerName}". '
        'Verificá que esté encendida y emparejada.',
      );
    }

    // Con plantilla diseñada: la etiqueta se dibuja entera como bitmap
    // (posiciones libres de los campos) y se imprime como raster.
    if (settings.useTemplate) {
      final template = await LabelTemplate.load();
      if (template != null && template.fields.isNotEmpty) {
        final List<int> bytes = settings.needsTspl2 || settings.printerType == 'tsc'
            ? await _buildTspl2Raster(label, settings, template, n)
            : await _buildEscPosRaster(label, settings, template, n);
        await _writeBytes(bytes);
        return;
      }
    }

    // Layout fijo (sin plantilla): el lenguaje lo decide la configuración:
    // 'tsc' → TSPL2 (TSC Alpha-3RB, el sensor posiciona cada etiqueta),
    // 'escpos' → ESC/POS (3nStar y TSC en modo recibo).
    final List<int> bytes = (settings.printerType == 'tsc' ||
            settings.needsTspl2)
        ? await _buildTspl2(label, settings, n)
        : await _buildEscPos(label, settings, n);

    await _writeBytes(bytes);
  }

  Future<void> _writeBytes(List<int> bytes) async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw Exception('Se perdió la conexión con la impresora.');
    }
    try {
      // Enviar en chunks para no saturar el buffer del SPP.
      const chunkSize = 512;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end =
            (i + chunkSize) < bytes.length ? (i + chunkSize) : bytes.length;
        conn.output.add(Uint8List.fromList(bytes.sublist(i, end)));
        await conn.output.allSent;
        await Future.delayed(const Duration(milliseconds: 20));
      }
      await conn.output.allSent;
    } catch (e) {
      await disconnect();
      throw Exception('Error enviando datos a la impresora: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Raster con plantilla diseñada
  // ══════════════════════════════════════════════════════════════

  Future<List<int>> _buildEscPosRaster(
    LabelData label,
    LabelSettings settings,
    LabelTemplate template,
    int copies,
  ) async {
    final paper = settings.widthMm >= 70 ? PaperSize.mm80 : PaperSize.mm58;
    // El ancho imprimible manda: mm58 = 384 dots, mm80 = 576 dots.
    final printable = paper == PaperSize.mm80 ? 576.0 : 384.0;
    final dotsPerMm = printable / settings.widthMm;
    final image = await LabelRaster.render(
      label: label,
      settings: settings,
      template: template,
      dotsPerMm: dotsPerMm,
    );
    final bytes = await LabelRaster.toEscPosRaster(image, paper);
    image.dispose();
    // Feed entre copias — el sensor posiciona la siguiente etiqueta
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    return bytes + generator.feed(3);
  }

  Future<List<int>> _buildTspl2Raster(
    LabelData label,
    LabelSettings settings,
    LabelTemplate template,
    int copies,
  ) async {
    // TSC: 203 dpi = 8 dots/mm, bitmap del tamaño exacto de la etiqueta.
    const dotsPerMm = 8.0;
    final image = await LabelRaster.render(
      label: label,
      settings: settings,
      template: template,
      dotsPerMm: dotsPerMm,
    );
    final bytes = await LabelRaster.toTspl2Raster(
      image,
      xDots: 0,
      yDots: 0,
      copies: copies,
      filename: 'SZLABEL.BMP',
    );
    image.dispose();
    return bytes;
  }

  // ══════════════════════════════════════════════════════════════
  // ESC/POS (3nStar y TSC en modo recibo continuo)
  // ══════════════════════════════════════════════════════════════

  Future<List<int>> _buildEscPos(
    LabelData label,
    LabelSettings settings,
    int copies,
  ) async {
    final paper = settings.widthMm >= 70 ? PaperSize.mm80 : PaperSize.mm58;
    // Perfil default: CP437/CP850, soporta acentos castellanos.
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);

    List<int> out = [];
    out += generator.reset();
    for (var c = 0; c < copies; c++) {
      // Nombre del producto (wrap según columnas de la paper)
      out += generator.text(
        label.itemName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size1,
          height: PosTextSize.size1,
        ),
        maxCharsPerLine: paper == PaperSize.mm80 ? 32 : 21,
      );

      // Unidad de medida
      out += generator.text(
        label.uom,
        styles: const PosStyles(align: PosAlign.center, bold: false),
      );

      // Precio grande (doble ancho/alto)
      out += generator.text(
        label.priceText,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          width: PosTextSize.size2,
          height: PosTextSize.size2,
        ),
      );

      // Código de barras (nativo de la impresora: nítido)
      final bc = _escPosBarcode(label.barcode);
      out += generator.emptyLines(1);
      if (bc != null) {
        out += generator.barcode(
          bc,
          width: 2,
          height: 80,
          align: PosAlign.center,
          textPos: BarcodeText.below,
          font: BarcodeFont.fontB,
        );
      } else {
        out += generator.text(
          label.barcode,
          styles: const PosStyles(align: PosAlign.center),
        );
      }

      // Feed — el sensor de la impresora posiciona la siguiente etiqueta
      out += generator.feed(3);
    }
    out += generator.reset();
    return out;
  }

  /// Construye el objeto Barcode de esc_pos_utils según el contenido.
  /// El caller normaliza con bestBarcodeFor() antes, así EAN13 siempre
  /// llega con 13 dígitos válidos.
  Barcode? _escPosBarcode(String code) {
    try {
      if (code.length == 13 && int.tryParse(code) != null) {
        return Barcode.ean13(code.split(''));
      }
      if (code.length == 8 && int.tryParse(code) != null) {
        return Barcode.ean8(code.split(''));
      }
      if (code.length >= 2) {
        return Barcode.code128(code.split(''));
      }
    } catch (_) {}
    return null;
  }

  // ══════════════════════════════════════════════════════════════
  // TSPL2 (TSC Alpha-3RB — troquelada con gap / marca negra)
  // ══════════════════════════════════════════════════════════════

  List<int> _buildTspl2(
    LabelData label,
    LabelSettings settings,
    int copies,
  ) {
    final w = settings.widthMm;
    final h = settings.heightMm;
    // 203 dpi ≈ 8 dots/mm
    final wDots = w * 8;

    final sb = StringBuffer();
    sb.write('SIZE $w mm,$h mm\r\n');
    switch (settings.paperType) {
      case 'gap':
        sb.write('GAP 2 mm,0\r\n');
        break;
      case 'blackmark':
        sb.write('BLACK MARK 3 mm,10\r\n');
        break;
      default:
        break; // continuo: sin comando de papel
    }
    sb.write('DIRECTION 1,0\r\n');
    sb.write('CLS\r\n');

    // Nombre (con wrap simple por caracteres)
    final nameLines = _wrapText(_sanitizeTspl2(label.itemName), 24);
    var y = 8;
    for (final line in nameLines.take(3)) {
      sb.write('TEXT 8,$y,"3",0,1,1,"$line"\r\n');
      y += 28;
    }

    // Unidad
    sb.write('TEXT 8,$y,"2",0,1,1,"${_sanitizeTspl2(label.uom)}"\r\n');
    y += 34;

    // Precio grande (BLOCK con magnificación 3x3)
    sb.write(
      'BLOCK 8,$y,${wDots - 16},56,3,0,3,3,"${_sanitizeTspl2(label.priceText)}"\r\n',
    );
    y += 64;

    // Código de barras
    final barcode = label.barcode;
    final barHeight = (h * 8 - y - 16).clamp(40, 120);
    sb.write(
      'BARCODE 8,$y,"${_tsplBarcodeType(barcode)}",$barHeight,1,0,2,3,"$barcode"\r\n',
    );

    sb.write('PRINT $copies,1\r\n');
    return latin1.encode(_asciiOnly(sb.toString()));
  }

  String _tsplBarcodeType(String code) {
    if (code.length == 13 && int.tryParse(code) != null) return 'EAN13';
    if (code.length == 8 && int.tryParse(code) != null) return 'EAN8';
    return 'CODE128';
  }

  /// TSPL2 con firmware clásico no lleva UTF-8: se limpian acentos/emojis.
  String _sanitizeTspl2(String s) => _asciiOnly(s);

  String _asciiOnly(String s) {
    const map = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u',
      'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U',
      'ñ': 'n', 'Ñ': 'N', '°': '', '"': "'", '“': "'", '”': "'",
    };
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(map[ch] ?? (rune < 128 ? ch : ''));
    }
    return buffer.toString();
  }

  List<String> _wrapText(String text, int width) {
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if (('$current $word').length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }
}

// ══════════════════════════════════════════════════════════════
// Utilidades de códigos de barras (check digits)
// ══════════════════════════════════════════════════════════════

/// Valida el dígito verificador de un EAN-13.
bool isValidEan13(String code) {
  if (code.length != 13 || int.tryParse(code) == null) return false;
  return _eanCheckDigit(code.substring(0, 12)) == code[12];
}

/// Valida el dígito verificador de un EAN-8.
bool isValidEan8(String code) {
  if (code.length != 8 || int.tryParse(code) == null) return false;
  return _eanCheckDigit(code.substring(0, 7)) == code[7];
}

/// Completa un EAN-13 con su dígito verificador (recibe 12 dígitos).
String completeEan13(String code) {
  final base = code.padRight(12, '0').substring(0, 12);
  return base + _eanCheckDigit(base);
}

String _eanCheckDigit(String base) {
  var sum = 0;
  for (var i = 0; i < base.length; i++) {
    final digit = int.parse(base[i]);
    // En EAN, desde la derecha: posiciones impares x3
    final factor = (base.length - i) % 2 == 1 ? 3 : 1;
    sum += digit * factor;
  }
  return ((10 - (sum % 10)) % 10).toString();
}

/// Devuelve el mejor código de barras imprimible:
/// EAN-13 válido (completando check digit si falta) → EAN-8 → el original
/// (CODE128 acepta cualquier contenido).
String bestBarcodeFor(String raw) {
  final code = raw.trim();
  if (code.length == 13 && int.tryParse(code) != null && isValidEan13(code)) {
    return code;
  }
  if (code.length == 12 && int.tryParse(code) != null) {
    return completeEan13(code);
  }
  if (code.length == 8 && int.tryParse(code) != null && isValidEan8(code)) {
    return code;
  }
  return code;
}
