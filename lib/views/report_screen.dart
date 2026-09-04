import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/inventory_provider.dart';
import '../models/inventory_row.dart';

/// Pantalla de reporte final con tabla completa y opciones de exportación.
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final items = provider.scannedItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('📋 Reporte de Inventario'),
        actions: [
          IconButton(
            onPressed: items.isEmpty ? null : () => _shareReport(context),
            icon: const Icon(Icons.share),
            tooltip: 'Compartir por correo/WhatsApp',
          ),
          IconButton(
            onPressed: items.isEmpty ? null : () => _exportExcel(context),
            icon: const Icon(Icons.file_download),
            tooltip: 'Descargar Excel',
          ),
          IconButton(
            onPressed: items.isEmpty ? null : () => _sendToErpNext(context),
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Enviar a ERPNext',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).primaryColor,
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _summaryChip(Icons.inventory, 'Productos',
                    '${provider.uniqueProducts}'),
                _summaryChip(Icons.production_quantity_limits, 'Unidades',
                    '${provider.totalUnitsScanned}'),
                _summaryChip(Icons.attach_money, 'Valor Total',
                    'L${provider.totalInventoryValue.toStringAsFixed(2)}'),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No hay productos escaneados'))
                : _buildDataTable(context, items, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(
    BuildContext context,
    List<InventoryRow> items,
    InventoryProvider provider,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey[100]),
          columns: const [
            DataColumn(
                label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Barcode Escaneado',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Código ERP',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Nombre',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label:
                    Text('UOM', style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Cant.',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Costo Unit.',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Costo Total',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Estado',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('Acciones',
                    style: TextStyle(fontWeight: FontWeight.bold))),
          ],
          rows: [
            ...items.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              return DataRow(cells: [
                DataCell(Text('${i + 1}')),
                DataCell(Text(row.displayCode,
                    style: const TextStyle(fontFamily: 'monospace'))),
                DataCell(Text(row.itemCode,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                DataCell(SizedBox(
                    width: 200,
                    child: Text(row.itemName,
                        overflow: TextOverflow.ellipsis))),
                DataCell(Text(row.stockUom)),
                DataCell(Text('${row.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text('L${row.unitCost.toStringAsFixed(2)}')),
                DataCell(Text(
                  'L${row.totalCost.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: row.totalCost > 0 ? Colors.teal[800] : Colors.grey,
                  ),
                )),
                DataCell(
                  row.hasCost
                      ? const Chip(
                          label: Text('OK',
                              style: TextStyle(fontSize: 10)),
                          backgroundColor: Colors.green)
                      : const Chip(
                          label: Text('Sin costo',
                              style: TextStyle(fontSize: 10)),
                          backgroundColor: Colors.orange),
                ),
                DataCell(IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  color: Colors.red,
                  onPressed: () => provider.removeItem(row.itemCode),
                )),
              ]);
            }),
            DataRow(cells: [
              const DataCell(Text('')),
              const DataCell(Text('')),
              const DataCell(Text('')),
              const DataCell(Text('TOTAL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              const DataCell(Text('')),
              DataCell(Text('${provider.totalUnitsScanned}',
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              const DataCell(Text('')),
              DataCell(Text(
                'L${provider.totalInventoryValue.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.green[900],
                ),
              )),
              const DataCell(Text('')),
              const DataCell(Text('')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Future<void> _shareReport(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    final bytes = provider.generateExcelReport();
    if (bytes == null) return;

    try {
      final dir = await getTemporaryDirectory();
      final now = DateTime.now();
      final fileName =
          'inventario_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '📦 Reporte de inventario - ${now.day}/${now.month}/${now.year}',
        subject: 'Inventario Superzito',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al compartir: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportExcel(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    final bytes = provider.generateExcelReport();
    if (bytes == null) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar inventario',
      fileName: 'inventario_$timestamp.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Excel descargado: inventario_$timestamp.xlsx'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _sendToErpNext(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    final items = provider.toStockReconciliationItems();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No hay items con costo para enviar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final warehouse = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('🏭 Stock Reconciliation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Se enviarán ${items.length} items a ERPNext como Stock Reconciliation.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Almacén (Warehouse)',
                  hintText: 'ej: Almacén Principal - CLP',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );

    if (warehouse == null || warehouse.isEmpty) return;

    try {
      final result = await provider.sendToErpNext(warehouseCode: warehouse);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('✅ Stock Reconciliation creado: ${result['name'] ?? 'OK'}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
