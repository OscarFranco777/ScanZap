import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';

/// Home screen — diseño moderno tipo dashboard con stats + módulos cards.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // ─── Colores del theme ───
  static const _navy = Color(0xFF1B2A4A);
  static const _accent = Color(0xFF26C6DA);
  static const _bg = Color(0xFFF2F4F8);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 600;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Header ───
              _buildHeader(provider, isSmall),

              // ─── Stats Card ───
              _buildStatsCard(provider, isSmall),

              const SizedBox(height: 24),

              // ─── Módulos section ───
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isSmall ? 20 : 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MÓDULOS PRINCIPALES',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey[800],
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        'Expanda',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ─── Grid de módulos ───
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isSmall ? 20 : 32),
                child: Column(
                  children: [
                    // Row 1: Órdenes de Compra + Recepción
                    Row(
                      children: [
                        Expanded(
                          child: _ModuleCard(
                            title: 'Órdenes de\nCompra',
                            icon: Icons.description_outlined,
                            bgColor: const Color(0xFFFFF3E0),
                            iconBgColor: const Color(0xFFFFE0B2),
                            iconColor: const Color(0xFFE65100),
                            onTap: () => Navigator.pushNamed(context, '/po-list'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ModuleCard(
                            title: 'Recepción de\nMercadería',
                            icon: Icons.local_shipping_outlined,
                            bgColor: const Color(0xFFE8F5E9),
                            iconBgColor: const Color(0xFFC8E6C9),
                            iconColor: const Color(0xFF2E7D32),
                            onTap: () => Navigator.pushNamed(context, '/mr-list'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Row 2: Reportes + Gestión de Inventario
                    Row(
                      children: [
                        Expanded(
                          child: _ModuleCard(
                            title: 'Reportes y\nAnalíticas',
                            icon: Icons.bar_chart_outlined,
                            bgColor: const Color(0xFFF3E5F5),
                            iconBgColor: const Color(0xFFE1BEE7),
                            iconColor: const Color(0xFF7B1FA2),
                            onTap: () => Navigator.pushNamed(context, '/report'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ModuleCard(
                            title: 'Gestión de\nInventario',
                            icon: Icons.qr_code_scanner,
                            bgColor: const Color(0xFFE0F7FA),
                            iconBgColor: const Color(0xFFB2EBF2),
                            iconColor: const Color(0xFF00838F),
                            onTap: () => Navigator.pushNamed(context, '/scanner'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ─── Config bar ───
              _buildConfigBar(context, isSmall),

              const SizedBox(height: 12),

              // ─── Footer stats ───
              _buildFooterStats(provider),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // HEADER
  // ══════════════════════════════════════════════════════════════

  Widget _buildHeader(InventoryProvider provider, bool isSmall) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isSmall ? 20 : 32, 16, isSmall ? 20 : 32, 16),
      decoration: const BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          // Logo circular
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          // Nombre
          const Expanded(
            child: Text(
              'SCAN-ZAP',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
          // Connection dot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: provider.isConnected
                  ? const Color(0xFF66BB6A).withValues(alpha: 0.2)
                  : const Color(0xFFEF6C00).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: provider.isConnected ? const Color(0xFF66BB6A) : const Color(0xFFEF6C00),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  provider.isConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: provider.isConnected ? const Color(0xFF66BB6A) : const Color(0xFFEF6C00),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // STATS CARD
  // ══════════════════════════════════════════════════════════════

  Widget _buildStatsCard(InventoryProvider provider, bool isSmall) {
    return Container(
      margin: EdgeInsets.fromLTRB(isSmall ? 20 : 32, 20, isSmall ? 20 : 32, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.inventory_2_outlined,
                  label: 'STOCK TOTAL',
                  value: '${provider.allItems.length}',
                  iconColor: _accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatItem(
                  icon: Icons.sync_outlined,
                  label: 'ÚLTIMA SINCRONIZACIÓN',
                  value: _formatLastSync(),
                  iconColor: _accent,
                  smallValue: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  icon: Icons.inventory_outlined,
                  label: 'ALERTAS DE COSTO',
                  value: '${provider.excelLoaded ? provider.excelService.filasConCosto : 0}',
                  iconColor: _accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatItem(
                  icon: Icons.warning_amber_rounded,
                  label: 'SIN COSTO',
                  value: '${provider.uniqueProducts}',
                  iconColor: const Color(0xFFFF7043),
                  valueColor: const Color(0xFFFF7043),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatLastSync() {
    final now = DateTime.now();
    final months = ['', 'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];
    return '${now.day} ${months[now.month]} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  // ══════════════════════════════════════════════════════════════
  // CONFIG BAR
  // ══════════════════════════════════════════════════════════════

  Widget _buildConfigBar(BuildContext context, bool isSmall) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 20 : 32),
      child: GestureDetector(
        onTap: () => Navigator.pushNamed(context, '/config'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFE8EDF3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 10),
              Text(
                'Configuración',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const Spacer(),
              Text(
                'Perfil de Usuario',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_outline, size: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // FOOTER STATS
  // ══════════════════════════════════════════════════════════════

  Widget _buildFooterStats(InventoryProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            'Total: ${provider.allItems.length} Productos',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(width: 1, height: 14, color: Colors.grey[400]),
          ),
          Icon(Icons.table_chart_outlined, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            'Con Costo: ${provider.excelLoaded ? provider.excelService.filasConCosto : 0}',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// STAT ITEM (dentro del card oscuro)
// ══════════════════════════════════════════════════════════════

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color? valueColor;
  final bool smallValue;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    this.valueColor,
    this.smallValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.6),
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: smallValue ? 12 : 18,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// MODULE CARD (cards grandes con ilustración)
// ══════════════════════════════════════════════════════════════

class _ModuleCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color bgColor;
  final Color iconBgColor;
  final Color iconColor;
  final VoidCallback onTap;
  final bool enabled;
  final String? badge;

  const _ModuleCard({
    required this.title,
    required this.icon,
    required this.bgColor,
    required this.iconBgColor,
    required this.iconColor,
    required this.onTap,
    this.enabled = true,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 160,
        decoration: BoxDecoration(
          color: enabled ? bgColor : bgColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Stack(
          children: [
            // Ilustración central
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: enabled
                          ? iconBgColor.withValues(alpha: 0.7)
                          : Colors.grey[300]!.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 32,
                      color: enabled ? iconColor : Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: enabled ? Colors.grey[800] : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),

            // Badge "Soon"
            if (badge != null)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: enabled ? iconColor : Colors.grey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
