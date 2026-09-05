import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';

/// Pantalla para cargar el archivo Excel con costos unitarios.
class ExcelUploadScreen extends StatefulWidget {
  const ExcelUploadScreen({super.key});

  @override
  State<ExcelUploadScreen> createState() => _ExcelUploadScreenState();
}

class _ExcelUploadScreenState extends State<ExcelUploadScreen> {
  bool _isProcessing = false;
  bool _showAllWarnings = false;
  int _codigoColumn = 0; // Columna A por defecto
  int _costoColumn = 2; // Columna C por defecto

  Future<void> _pickAndProcessFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true, // Importante para web
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isProcessing = true);

      final file = result.files.first;
      final provider = context.read<InventoryProvider>();

      provider.processExcel(
        fileBytes: file.bytes!,
        fileName: file.name,
        codigoColumn: _codigoColumn,
        costoColumn: _costoColumn,
      );

      setState(() => _isProcessing = false);

      if (provider.excelLoaded) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Excel cargado: ${provider.excelService.filasConCosto} productos con costo',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ No se encontraron costos. Revisá las columnas.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('📊 Cargar Costos Excel')),
      body: Column(
        children: [
          // Contenido scrolleable
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icono
                  Icon(Icons.upload_file, size: 64, color: Colors.teal[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Archivo de Costos Unitarios',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cargá un archivo Excel (.xlsx) con los costos de cada producto.\n'
                    'Se espera: Columna A = Código, Columna B = Nombre, Columna C = Costo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),

                  // Configuración de columnas
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configuración de columnas:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  isExpanded: true,
                                  initialValue: _codigoColumn,
                                  decoration: const InputDecoration(
                                    labelText: 'Cód.',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: List.generate(26, (i) {
                                    final letter = String.fromCharCode(65 + i);
                                    return DropdownMenuItem(
                                      value: i,
                                      child: Text(
                                        'Col $letter',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  }),
                                  onChanged: (v) =>
                                      setState(() => _codigoColumn = v ?? 0),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  isExpanded: true,
                                  initialValue: _costoColumn,
                                  decoration: const InputDecoration(
                                    labelText: 'Costo',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                  ),
                                  items: List.generate(26, (i) {
                                    final letter = String.fromCharCode(65 + i);
                                    return DropdownMenuItem(
                                      value: i,
                                      child: Text(
                                        'Col $letter',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    );
                                  }),
                                  onChanged: (v) =>
                                      setState(() => _costoColumn = v ?? 2),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Botón de carga
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _pickAndProcessFile,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_upload),
                      label: Text(
                        _isProcessing
                            ? 'Procesando...'
                            : 'Seleccionar Archivo Excel',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Resumen del Excel cargado
                  if (provider.excelLoaded) ...[
                    Card(
                      color: Colors.green[50],
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Excel cargado: ${provider.excelFileName}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '📦 Productos con costo: ${provider.excelService.filasConCosto}',
                            ),
                            Text(
                              '📋 Total de filas leídas: ${provider.excelService.totalFilas}',
                            ),
                            if (provider.isConnected)
                              Text(
                                '🔗 Coincidencias con ERPNext: ${provider.excelMatchCount}',
                                style: TextStyle(
                                  color: provider.excelMatchCount > 0
                                      ? Colors.green[800]
                                      : Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Errores del Excel
                  if (provider.excelService.errores.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Colors.orange[50],
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '⚠️ Advertencias:',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                Text(
                                  '${provider.excelService.errores.length} total',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...provider.excelService.errores
                                .take(_showAllWarnings ? 50 : 3)
                                .map(
                                  (e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      '• $e',
                                      style: const TextStyle(fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                            if (provider.excelService.errores.length > 3)
                              GestureDetector(
                                onTap: () => setState(
                                  () => _showAllWarnings = !_showAllWarnings,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _showAllWarnings
                                        ? '▲ Ocultar'
                                        : '▼ Ver las ${provider.excelService.errores.length} advertencias',
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                      fontSize: 12,
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
            ),
          ),

          // Botón continuar — SIEMPRE visible al fondo
          if (provider.isReady)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/home'),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Continuar al Inventario'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
