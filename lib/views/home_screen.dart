import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';

/// Home screen — diseño moderno tipo Odoo con módulos en grid.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ─── Header con conexión y settings ───
            SliverToBoxAdapter(
              child: _ConnectionHeader(provider: provider, isSmallScreen: isSmallScreen),
            ),

            // ─── Módulos grid ───
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 16 : 32,
                vertical: 8,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Módulos',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // ─── Grid de módulos ───
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 16 : 32,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isSmallScreen ? 2 : 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: isSmallScreen ? 1.0 : 1.1,
                ),
                delegate: SliverChildListDelegate([
                  // Órdenes de Compra
                  _ModuleTile(
                    icon: Icons.shopping_cart_outlined,
                    title: 'Órdenes\nde Compra',
                    color: const Color(0xFFFF7043),
                    enabled: provider.isConnected,
                    onTap: () => Navigator.pushNamed(context, '/po-list'),
                  ),

                  // Recepción de Mercadería
                  _ModuleTile(
                    icon: Icons.inventory_2_outlined,
                    title: 'Recepción\nde Mercadería',
                    color: const Color(0xFF5C6BC0),
                    enabled: provider.isConnected,
                    onTap: () => Navigator.pushNamed(context, '/mr-list'),
                  ),

                  // Escáner
                  _ModuleTile(
                    icon: Icons.qr_code_scanner,
                    title: 'Escanear\nInventario',
                    color: const Color(0xFF66BB6A),
                    enabled: provider.isReady,
                    onTap: () => Navigator.pushNamed(context, '/scanner'),
                  ),

                  // Reporte
                  _ModuleTile(
                    icon: Icons.assessment_outlined,
                    title: 'Ver\nReporte',
                    color: const Color(0xFFAB47BC),
                    enabled: provider.uniqueProducts > 0,
                    onTap: () => Navigator.pushNamed(context, '/report'),
                  ),

                  // Cargar Costos
                  _ModuleTile(
                    icon: Icons.table_chart_outlined,
                    title: 'Cargar\nCostos',
                    color: const Color(0xFF26C6DA),
                    onTap: () => Navigator.pushNamed(context, '/excel'),
                  ),

                  // Configuración
                  _ModuleTile(
                    icon: Icons.settings_outlined,
                    title: 'Configuración',
                    color: const Color(0xFF78909C),
                    onTap: () => Navigator.pushNamed(context, '/config'),
                  ),
                ]),
              ),
            ),

            // ─── Info footer ───
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(
                  left: isSmallScreen ? 16 : 32,
                  right: isSmallScreen ? 16 : 32,
                  top: 20,
                  bottom: 32,
                ),
                child: _StatsBar(provider: provider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Header compacto con estado de conexión y botón de settings.
class _ConnectionHeader extends StatelessWidget {
  final InventoryProvider provider;
  final bool isSmallScreen;

  const _ConnectionHeader({required this.provider, required this.isSmallScreen});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isSmallScreen ? 16 : 32,
        12,
        isSmallScreen ? 16 : 32,
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: provider.isConnected
                  ? const Color(0xFF43A047).withValues(alpha: 0.1)
                  : const Color(0xFFEF6C00).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              color: provider.isConnected ? const Color(0xFF43A047) : const Color(0xFFEF6C00),
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          // Texto expandible
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ScanZap',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: provider.isConnected ? const Color(0xFF43A047) : const Color(0xFFEF6C00),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        provider.isConnected
                            ? '${provider.loggedUser} · ${provider.allItems.length} items'
                            : 'Sin conexión',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Botón de configuración
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/config'),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.settings_outlined,
                color: Colors.grey[600],
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Módulo en el grid — cuadrado con icono grande.
class _ModuleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  const _ModuleTile({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? Colors.white : Colors.grey[100],
      borderRadius: BorderRadius.circular(16),
      elevation: enabled ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled
                      ? color.withValues(alpha: 0.12)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: enabled ? color : Colors.grey[400],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: enabled ? Colors.grey[800] : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barra de estadísticas sutil abajo.
class _StatsBar extends StatelessWidget {
  final InventoryProvider provider;

  const _StatsBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (!provider.isConnected && !provider.excelLoaded) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          if (provider.isConnected) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  '${provider.allItems.length} productos',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
          if (provider.excelLoaded) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.table_chart_outlined, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  '${provider.excelService.filasConCosto} con costo',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
          Text(
            'v1.0',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
