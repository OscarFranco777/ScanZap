import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart' as bc;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, FontWeight, TextAlign;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import '../models/label_settings.dart';
import '../models/label_template.dart';
import 'label_printer_service.dart' show LabelData;

/// Renderiza la etiqueta según la plantilla diseñada y la convierte a
/// bitmap monocromo para impresión térmica.
///
/// Un solo camino para ambos lenguajes:
///  - ESC/POS  → raster nativo del generador (generator.image)
///  - TSPL2    → BMP monocromo 1-bit via DOWNLOAD + PUTBMP
///
/// Todo se dibuja a [dotsPerMm] px por mm (203 dpi ≈ 8 dots/mm).
class LabelRaster {
  static ui.Image? _logoCache;

  /// Renderiza la plantilla sobre los datos de la etiqueta.
  /// [dotsPerMm]: resolución del bitmap (ESC/POS usa el ancho imprimible
  /// del papel; TSPL2 usa 8 = 203 dpi exactos).
  static Future<ui.Image> render({
    required LabelData label,
    required LabelSettings settings,
    required LabelTemplate template,
    required double dotsPerMm,
  }) async {
    final pxW = (settings.widthMm * dotsPerMm).round();
    final pxH = (settings.heightMm * dotsPerMm).round();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    // Fondo blanco (lo que no se imprime = blanco = sin calor)
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    for (final f in template.fields) {
      final rect = ui.Rect.fromLTWH(
        f.x * dotsPerMm,
        f.y * dotsPerMm,
        f.w * dotsPerMm,
        f.h * dotsPerMm,
      );
      try {
        switch (f.type) {
          case 'name':
            await _drawText(canvas, label.itemName, rect, f, dotsPerMm,
                wrap: true, bold: f.bold);
            break;
          case 'price':
            await _drawText(canvas, label.priceText, rect, f, dotsPerMm,
                wrap: false, bold: true);
            break;
          case 'code':
            await _drawText(canvas, label.barcode, rect, f, dotsPerMm,
                wrap: false, bold: false);
            break;
          case 'barcode':
            _drawBarcode(canvas, label.barcode, rect);
            break;
          case 'logo':
            await _drawLogo(canvas, rect);
            break;
        }
      } catch (_) {
        // Un campo que falla no debe matar toda la etiqueta.
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(pxW, pxH);
    return image;
  }

  // ══════════════════════════════════════════════════════════════
  // Campos
  // ══════════════════════════════════════════════════════════════

  static Future<void> _drawText(
    ui.Canvas canvas,
    String text,
    ui.Rect rect,
    LabelField f,
    double dotsPerMm, {
    required bool wrap,
    required bool bold,
  }) async {
    if (text.isEmpty) return;
    var fontSize = (f.fontMm * dotsPerMm).clamp(6.0, 300.0);

    // Ajustar el texto al recuadro: si no cabe, reducir la fuente hasta
    // que quepa (mínimo 50% del tamaño pedido).
    for (var attempt = 0; attempt < 12; attempt++) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: const ui.Color(0xFF000000),
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        textAlign: TextAlign.center,
        maxLines: wrap ? 8 : 1,
      );
      tp.layout(maxWidth: rect.width);
      if (tp.height <= rect.height || fontSize <= f.fontMm * dotsPerMm * 0.5) {
        // Centrado dentro del recuadro
        final dx = (rect.width - tp.width) / 2;
        final dy = (rect.height - tp.height) / 2;
        tp.paint(canvas, ui.Offset(rect.left + dx, rect.top + dy));
        return;
      }
      fontSize *= 0.88;
    }
  }

  static void _drawBarcode(ui.Canvas canvas, String code, ui.Rect rect) {
    final clean = code.trim();
    if (clean.isEmpty) return;

    bc.Barcode barcode;
    if (clean.length == 13 && int.tryParse(clean) != null) {
      barcode = bc.Barcode.ean13();
    } else if (clean.length == 8 && int.tryParse(clean) != null) {
      barcode = bc.Barcode.ean8();
    } else {
      barcode = bc.Barcode.code128();
    }

    // Si el código no es un EAN válido (check digit mal, etc.), caemos a
    // Code128 en vez de reventar la impresión a mitad de camino.
    final data = Uint8List.fromList(utf8.encode(clean));
    try {
      barcode.verifyBytes(data);
    } on bc.BarcodeException {
      barcode = bc.Barcode.code128();
    }

    final bars = barcode.makeBytes(
      data,
      width: rect.width,
      height: rect.height,
    );

    final black = ui.Paint()..color = const ui.Color(0xFF000000);
    for (final bar in bars) {
      if (bar is bc.BarcodeBar && bar.black) {
        canvas.drawRect(
          ui.Rect.fromLTWH(
            rect.left + bar.left,
            rect.top + bar.top,
            bar.width,
            bar.height,
          ),
          black,
        );
      }
    }
  }

  static Future<void> _drawLogo(ui.Canvas canvas, ui.Rect rect) async {
    final logo = await _loadLogo();
    if (logo == null) return;

    // Ajustar el logo dentro del recuadro manteniendo aspecto.
    final lw = logo.width.toDouble();
    final lh = logo.height.toDouble();
    final scale = (rect.width / lw).clamp(0.0, rect.height / lh);
    final dw = lw * scale;
    final dh = lh * scale;
    final dx = rect.left + (rect.width - dw) / 2;
    final dy = rect.top + (rect.height - dh) / 2;

    canvas.drawImageRect(
      logo,
      ui.Rect.fromLTWH(0, 0, lw, lh),
      ui.Rect.fromLTWH(dx, dy, dw, dh),
      ui.Paint(),
    );
  }

  static Future<ui.Image?> _loadLogo() async {
    if (_logoCache != null) return _logoCache;
    try {
      final data = await rootBundle.load('assets/logo/superzito.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _logoCache = frame.image;
      return _logoCache;
    } catch (_) {
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // Encoders
  // ══════════════════════════════════════════════════════════════

  /// ESC/POS: raster nativo del generador (rotación/empaquetado internos).
  static Future<List<int>> toEscPosRaster(
    ui.Image image,
    PaperSize paper,
  ) async {
    final data =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) throw Exception('No se pudo procesar la etiqueta.');

    final im = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: data.buffer,
      numChannels: 4,
    );

    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    return generator.image(im);
  }

  /// TSPL2: BMP monocromo 1-bit → DOWNLOAD + PUTBMP (hex).
  /// Devuelve el bloque completo de comandos listos para enviar.
  static Future<List<int>> toTspl2Raster(
    ui.Image image, {
    required int xDots,
    required int yDots,
    required int copies,
    required String filename,
  }) async {
    final bmp = await _encodeBmp1Bit(image);
    final hex = _bytesToHex(bmp);

    final sb = StringBuffer();
    sb.write('DOWNLOAD "$filename",${bmp.length},$hex\r\n');
    sb.write('PUTBMP $xDots,$yDots,"$filename"\r\n');
    sb.write('PRINT $copies,1\r\n');
    return latin1.encode(sb.toString());
  }

  /// Convierte la imagen a BMP monocromo 1-bit (paleta negro/blanco).
  /// Filas bottom-up, alineadas a 4 bytes — formato BMP estándar.
  static Future<Uint8List> _encodeBmp1Bit(ui.Image image) async {
    final w = image.width;
    final h = image.height;
    final rowBytes = ((w + 31) ~/ 32) * 4;
    final pixelDataSize = rowBytes * h;
    final totalSize = 14 + 40 + 8 + pixelDataSize;

    final out = BytesBuilder();
    final header = ByteData(14);
    header.setUint8(0, 0x42); // 'B'
    header.setUint8(1, 0x4D); // 'M'
    header.setUint32(2, totalSize, Endian.little);
    header.setUint32(10, 62, Endian.little); // offset a los píxeles
    out.add(header.buffer.asUint8List());

    final info = ByteData(40);
    info.setUint32(0, 40, Endian.little);
    info.setInt32(4, w, Endian.little);
    info.setInt32(8, h, Endian.little); // bottom-up
    info.setUint16(12, 1, Endian.little); // planes
    info.setUint16(14, 1, Endian.little); // bits por pixel
    info.setUint32(16, 0, Endian.little); // sin compresión
    info.setUint32(20, pixelDataSize, Endian.little);
    info.setInt32(24, 3780, Endian.little); // 2835 ppm aprox
    info.setInt32(28, 3780, Endian.little);
    info.setUint32(32, 2, Endian.little); // colores en paleta
    info.setUint32(36, 2, Endian.little);
    out.add(info.buffer.asUint8List());

    // Paleta: índice 0 = negro, índice 1 = blanco
    out.add(Uint8List.fromList([0, 0, 0, 0, 255, 255, 255, 0]));

    // Píxeles: bit 0 = negro (índice 0), bit 1 = blanco (índice 1)
    final pixels = Uint8List(pixelDataSize);
    final data =
        await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final rgba = data!.buffer.asUint8List();
    for (var y = 0; y < h; y++) {
      // BMP va bottom-up: fila y de la imagen → fila (h-1-y) del BMP
      final dstRow = h - 1 - y;
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        // Luminancia: < 128 → negro
        final lum =
            (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        if (lum >= 128) {
          final byteIndex = dstRow * rowBytes + (x ~/ 8);
          pixels[byteIndex] |= (0x80 >> (x % 8));
        }
      }
    }
    out.add(pixels);
    return out.toBytes();
  }

  static String _bytesToHex(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      buf.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}
