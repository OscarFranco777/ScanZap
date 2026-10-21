import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/stock_entry_provider.dart';
import '../theme/app_design.dart';

/// Pantalla de lista de Entradas de Inventario (Stock Entry) — diseño dashboard.
class StockEntryListScreen extends StatefulWidget {
  const StockEntryListScreen({super.key});

  @override
  State<StockEntryListScreen> createState() => _StockEntryListScreenState();
}

class _StockEntryListScreenState extends State<StockEntryListScreen> {
  bool _statsExpanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StockEntryProvider>().fetchEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StockEntryProvider>();
    final entries = provider.entriesList;

    int drafts = 0, submitted = 0, cancelled = 0;
    for (final e in entries) {
      final ds = e['docstatus'] ?? 0;
      if (ds == 0) drafts++;
      if (ds == 1) submitted++;
      if (ds == 2) cancelled++;
    }

    return Scaffold(
      backgroundColor: AppDesign.bg,
      body: Column(
        children: [
          // ─── Header ───
          AppDesign.buildHeader(
            title: 'Entradas de Inventario',
            subtitle: '${entries.length} movimientos registrados',
            icon: Icons.swap_horiz,
            onBack: () => Navigator.pop(context),
            actions: [
              GestureDetector(
                onTap: () => provider.fetchEntries(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),

          // ─── Stats (colapsable) ───
          GestureDetector(
            onTap: () => setState(() => _statsExpanded = !_statsExpanded),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppDesign.navy,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppDesign.navy.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Header toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.analytics_outlined,
                            size: 16,
                            color: AppDesign.accent,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Resumen de Entradas',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          AnimatedRotation(
                            turns: _statsExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Stats content (animated)
                    if (_statsExpanded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        child: Column(
                          children: [
                            AppDesign.buildStatRow(
                              compact: true,
                              items: [
                                AppDesign.statBox(
                                  icon: Icons.swap_horiz,
                                  label: 'TOTAL ENTRADAS',
                                  value: '${entries.length}',
                                  compact: true,
                                ),
                                AppDesign.statBox(
                                  icon: Icons.edit_note,
                                  label: 'BORRADORES',
                                  value: '$drafts',
                                  valueColor: AppDesign.statusDraft,
                                  compact: true,
                                ),
                              ],
                            ),
                            AppDesign.buildStatRow(
                              compact: true,
                              items: [
                                AppDesign.statBox(
                                  icon: Icons.check_circle_outline,
                                  label: 'ENVIADAS',
                                  value: '$submitted',
                                  valueColor: AppDesign.statusSubmitted,
                                  compact: true,
                                ),
                                AppDesign.statBox(
                                  icon: Icons.cancel_outlined,
                                  label: 'CANCELADAS',
                                  value: '$cancelled',
                                  valueColor: AppDesign.statusCancelled,
                                  compact: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ─── Lista ───
          Expanded(
            child: provider.isLoading && entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? AppDesign.emptyState(
                        icon: Icons.inbox_outlined,
                        title: 'No hay entradas',
                        subtitle: 'Presioná el botón + para crear una nueva',
                      )
                    : RefreshIndicator(
                        onRefresh: () => provider.fetchEntries(),
                        child: ListView(
                          padding: const EdgeInsets.only(top: 8, bottom: 100),
                          children: [
                            AppDesign.sectionTitle('Lista de Entradas'),
                            for (final entry in entries)
                              _buildEntryCard(context, entry),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: AppDesign.fab(
        onPressed: () {
          context.read<StockEntryProvider>().clearCurrentEntry();
          Navigator.pushNamed(context, '/se-create');
        },
        icon: Icons.add,
        label: 'Nueva Entrada',
        color: AppDesign.tealIcon,
      ),
    );
  }

  Widget _buildEntryCard(BuildContext context, Map<String, dynamic> entry) {
    final name = entry['name'] ?? '';
    final type = (entry['stock_entry_type'] ?? '').toString();
    final date = entry['posting_date'] ?? '';
    final docstatus = entry['docstatus'] ?? 0;

    final statusText =
        docstatus == 0 ? 'Borrador' : (docstatus == 2 ? 'Cancelada' : 'Enviada');
    final statusColor = docstatus == 0
        ? AppDesign.statusDraft
        : (docstatus == 2 ? AppDesign.statusCancelled : AppDesign.statusSubmitted);

    return AppDesign.buildListCard(
      context: context,
      onTap: () async {
        context.read<StockEntryProvider>().loadEntry(name);
        final result = await Navigator.pushNamed(context, '/se-detail');
        if (result == true && context.mounted) {
          context.read<StockEntryProvider>().fetchEntries();
        }
      },
      child: Row(
        children: [
          AppDesign.circleAvatar(
            icon: Icons.swap_horiz,
            bgColor: statusColor,
            iconColor: statusColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF1B2A4A),
                  ),
                ),
                if (type.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    type,
                    style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  date.isNotEmpty
                      ? DateFormat('dd/MM/yyyy')
                          .format(DateTime.tryParse(date) ?? DateTime.now())
                      : '',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ],
            ),
          ),
          AppDesign.statusBadge(statusText, statusColor),
        ],
      ),
    );
  }
}
