import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/inventory_provider.dart';
import '../models/inventory_row.dart';
import '../theme/app_design.dart';

/// Pantalla de reporte final — diseño dashboard moderno.
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final items = provider.scannedItems;

    return Scaffold(
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── Header ───
          AppDesign.buildHeader(
            title: 'Reporte de Inventario',
            subtitle: '${provider.uniqueProducts} productos • L${provider.totalInventoryValue.toStringAsFixed(2)}',
            icon: Icons.assessment_outlined,
            onBack: () => Navigator.pop(context),
            actions: [
              GestureDetector(
                onTap: items.isEmpty ? null : () => _shareReport(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.share, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: items.isEmpty ? null : () => _exportExcel(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.file_download, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),

          // ─── Stats ───
          AppDesign.buildStatsCard(
            children: [
              AppDesign.buildStatRow(
                items: [
                  AppDesign.statBox(
                    icon: Icons.inventory_2_outlined,
                    label: 'PRODUCTOS',
                    value: '${provider.uniqueProducts}',
                  ),
                  AppDesign.statBox(
                    icon: Icons.numbers,
                    label: 'UNIDADES',
                    value: '${provider.totalUnitsScanned}',
                  ),
                ],
              ),
              AppDesign.buildStatRow(
                items: [
                  AppDesign.statBox(
                    icon: Icons.attach_money,
                    label: 'VALOR TOTAL',
                    value: 'L${provider.totalInventoryValue.toStringAsFixed(2)}',
                  ),
                  AppDesign.statBox(
                    icon: Icons.table_chart_outlined,
                    label: 'CON COSTO',
                    value: '${provider.excelLoaded ? provider.excelService.filasConCosto : 0}',
                  ),
                ],
              ),
            ],
          ),

          // ─── Acciones ───
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                _buildActionCard(
                  icon: Icons.share,
                  label: 'Compartir',
                  bgColor: AppDesign.tealLight,
                  iconColor: AppDesign.tealIcon,
                  onTap: items.isEmpty ? null : () => _shareReport(context),
                ),
                const SizedBox(width: 10),
                _buildActionCard(
                  icon: Icons.file_download,
                  label: 'Descargar',
                  bgColor: AppDesign.blueLight,
                  iconColor: AppDesign.blueIcon,
                  onTap: items.isEmpty ? null : () => _exportExcel(context),
                ),
                const SizedBox(width: 10),
                _buildActionCard(
                  icon: Icons.cloud_upload,
                  label: 'Enviar ERP',
                  bgColor: AppDesign.purpleLight,
                  iconColor: AppDesign.purpleIcon,
                  onTap: items.isEmpty ? null : () => _sendToErpNext(context),
                ),
              ],
            ),
          ),

          // ─── Tabla ───
          Expanded(
            child: items.isEmpty
                ? AppDesign.emptyState(
                    icon: Icons.table_chart_outlined,
                    title: 'No hay productos escaneados',
                    subtitle: 'Escaneá productos para ver el reporte',
                  )
                : _buildDataTable(context, items, provider),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: onTap != null ? bgColor : bgColor.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: onTap != null ? iconColor : Colors.grey[400]),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: onTap != null ? iconColor : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
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
          headingRowColor: WidgetStateProperty.all(AppDesign.navy.withValues(alpha: 0.05)),
          headingTextStyle: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.grey[700],
            fontSize: 12,
          ),
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Barcode')),
            DataColumn(label: Text('Código ERP')),
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('UOM')),
            DataColumn(label: Text('Cant.')),
            DataColumn(label: Text('Costo Unit.')),
            DataColumn(label: Text('Costo Total')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('Acciones')),
          ],
          rows: [
            ...items.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              return DataRow(cells: [
                DataCell(Text('${i + 1}')),
                DataCell(Text(row.displayCode,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                DataCell(Text(row.itemCode,
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12))),
                DataCell(SizedBox(
                    width: 200,
                    child: Text(row.itemName,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))),
                DataCell(Text(row.stockUom)),
                DataCell(Text('${row.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text('L${row.unitCost.toStringAsFixed(2)}')),
                DataCell(Text(
                  'L${row.totalCost.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: row.totalCost > 0 ? AppDesign.tealIcon : Colors.grey,
                  ),
                )),
                DataCell(
                  row.hasCost
                      ? AppDesign.statusBadge('OK', AppDesign.statusSubmitted)
                      : AppDesign.statusBadge('Sin costo', AppDesign.statusDraft),
                ),
                DataCell(IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppDesign.statusCancelled,
                  onPressed: () => provider.removeItem(row.itemCode),
                )),
              ]);
            }),
            DataRow(cells: [
              const DataCell(Text('')),
              const DataCell(Text('')),
              const DataCell(Text('')),
              DataCell(Text('TOTAL',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppDesign.navy))),
              const DataCell(Text('')),
              DataCell(Text('${provider.totalUnitsScanned}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
              const DataCell(Text('')),
              DataCell(Text(
                'L${provider.totalInventoryValue.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppDesign.tealIcon,
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

  // ══════════════════════════════════════════════════════════════
  // ACCIONES
  // ══════════════════════════════════════════════════════════════

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
          backgroundColor: AppDesign.statusCancelled,
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
          backgroundColor: AppDesign.statusSubmitted,
        ),
      );
    }
  }

  void _sendToErpNext(BuildContext context) async {
    final provider = context.read<InventoryProvider>();
    final items = provider.toStockReconciliationItems();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('⚠️ No hay items con costo para enviar'),
          backgroundColor: AppDesign.statusDraft,
        ),
      );
      return;
    }

    final warehouse = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Stock Reconciliation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Se enviarán ${items.length} items a ERPNext como Stock Reconciliation.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: 'Almacén (Warehouse)',
                  hintText: 'ej: Almacén Principal - CLP',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesign.navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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
          backgroundColor: AppDesign.statusSubmitted,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: AppDesign.statusCancelled),
      );
    }
  }
}
