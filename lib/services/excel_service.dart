import 'dart:typed_data';
import 'package:excel/excel.dart';

/// Servicio para parsear archivos Excel (.xlsx / .xls) en el navegador.
/// Extrae los costos unitarios de los productos por código de barras.
class ExcelService {
  /// Resultado del parsing del Excel.
  final Map<String, double> costoMap = {};
  final List<String> errores = [];
  int totalFilas = 0;
  int filasConCosto = 0;

  /// Parsea un archivo Excel y construye el mapa de costos.
  ///
  /// [fileBytes] - Contenido del archivo en bytes
  /// [codigoColumn] - Índice de columna del código de barras (default: 0 = columna A)
  /// [costoColumn] - Índice de columna del costo unitario (default: 2 = columna C)
  /// [skipHeader] - Si true, salta la primera fila (default: true)
  /// [sheetIndex] - Índice de la hoja a leer (default: 0 = primera hoja)
  void parseExcel(
    Uint8List fileBytes, {
    int codigoColumn = 0,
    int costoColumn = 2,
    int nombreColumn = 1,
    bool skipHeader = true,
    int sheetIndex = 0,
  }) {
    costoMap.clear();
    errores.clear();
    totalFilas = 0;
    filasConCosto = 0;

    try {
      final excel = Excel.decodeBytes(fileBytes);

      if (excel.tables.isEmpty) {
        errores.add('El archivo no contiene hojas de cálculo.');
        return;
      }

      final sheetName = excel.tables.keys.elementAt(
        sheetIndex.clamp(0, excel.tables.length - 1),
      );
      final sheet = excel.tables[sheetName];

      if (sheet == null || sheet.maxRows == 0) {
        errores.add('La hoja "$sheetName" está vacía.');
        return;
      }

      final startRow = skipHeader ? 1 : 0;
      totalFilas = sheet.maxRows - startRow;

      for (int row = startRow; row < sheet.maxRows; row++) {
        try {
          // Leer código de barras / item code
          final codeCell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: codigoColumn, rowIndex: row),
          );
          // Extraer código preservando integridad (ceros a la izquierda incluidos)
          String codigo = '';
          final cellVal = codeCell.value;
          if (cellVal is TextCellValue) {
            // Celda de texto → preserva ceros a la izquierda tal cual
            codigo = cellVal.value.toString().trim();
          } else if (cellVal is DoubleCellValue) {
            // Celda numérica → convertir a int para quitar .0 (los ceros a la izquierda
            // se perdieron al guardar como número en Excel — lamentablemente irrecuperable)
            codigo = cellVal.value.toInt().toString();
          } else if (cellVal is IntCellValue) {
            codigo = cellVal.value.toString();
          } else if (cellVal != null) {
            codigo = cellVal.toString().trim().replaceAll(RegExp(r'\.0$'), '');
          }
          if (codigo.isEmpty) continue;

          // Leer costo unitario
          final costoCell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: costoColumn, rowIndex: row),
          );
          final costoStr = costoCell.value?.toString().trim() ?? '0';

          // Intentar parsear el costo (maneja comas y puntos decimales)
          final costo = _parseCosto(costoStr);

          if (costo != null && costo > 0) {
            // Normalizar el código: quitar espacios, pasar a mayúsculas
            final normalizedCode = codigo.replaceAll(RegExp(r'\s'), '').toUpperCase();
            costoMap[normalizedCode] = costo;
            // También indexar sin ceros a la izquierda (por si ERPNext lo tiene así)
            final stripped = normalizedCode.replaceFirst(RegExp(r'^0+'), '');
            if (stripped != normalizedCode && stripped.isNotEmpty) {
              costoMap[stripped] = costo;
            }
            filasConCosto++;
          } else {
            errores.add('Fila ${row + 1}: costo inválido "$costoStr" para código "$codigo"');
          }
        } catch (e) {
          errores.add('Fila ${row + 1}: error de lectura - $e');
        }
      }
    } catch (e) {
      errores.add('Error al leer el archivo Excel: $e');
    }
  }

  /// Busca el costo de un producto por código.
  /// Busca con y sin ceros a la izquierda.
  double? getCost(String itemCode) {
    final normalized = itemCode.replaceAll(RegExp(r'\s'), '').toUpperCase();
    final stripped = normalized.replaceFirst(RegExp(r'^0+'), '');
    // Primero buscar con el código original
    final cost = costoMap[normalized];
    if (cost != null) return cost;
    // Si no, buscar sin ceros a la izquierda
    if (stripped != normalized) {
      return costoMap[stripped];
    }
    return null;
  }

  /// Intenta parsear un string a double, manejando formato latino (coma decimal).
  double? _parseCosto(String value) {
    if (value.isEmpty) return null;

    // Quitar símbolo de moneda y espacios (pero NO puntos — el punto es separador decimal en inglés)
    String cleaned = value.replaceAll(RegExp(r'[$€L£\s]'), '');

    // Si tiene coma Y punto, determinar cuál es el separador decimal
    if (cleaned.contains(',') && cleaned.contains('.')) {
      // Formato: 1,234.56 → punto es decimal
      if (cleaned.lastIndexOf(',') < cleaned.lastIndexOf('.')) {
        cleaned = cleaned.replaceAll(',', '');
      } else {
        // Formato: 1.234,56 → coma es decimal
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      }
    } else if (cleaned.contains(',')) {
      // Solo coma: puede ser decimal (12,50) o miles (1,234)
      final parts = cleaned.split(',');
      if (parts.last.length <= 2) {
        cleaned = cleaned.replaceAll(',', '.'); // Es decimal
      } else {
        cleaned = cleaned.replaceAll(',', ''); // Son miles
      }
    }

    return double.tryParse(cleaned);
  }
}
