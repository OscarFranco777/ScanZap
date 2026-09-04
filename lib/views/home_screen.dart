import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';

/// Home screen: muestra el estado de la conexión y acceso rápido a módulos.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('📦 Inventario ERPNext'),
        actions: [
          if (provider.isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.person, size: 16, color: Colors.green),
                  label: Text(provider.loggedUser, style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.green[50],
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Estado de conexión
            Card(
              color: provider.isConnected ? Colors.green[50] : Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      provider.isConnected ? Icons.cloud_done : Icons.cloud_off,
                      color: provider.isConnected ? Colors.green : Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.isConnected
                                ? 'Conectado como ${provider.loggedUser}'
                                : 'No conectado a ERPNext',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            provider.isConnected
                                ? '${provider.allItems.length} productos cargados'
                                : 'Necesitás configurar la conexión primero',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (provider.isConnected)
                      TextButton(
                        onPressed: () async {
                          await provider.disconnect();
                          if (context.mounted) {
                            Navigator.pushReplacementNamed(context, '/config');
                          }
                        },
                        child: const Text('Salir'),
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/config'),
                        child: const Text('Conectar'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Estado del Excel
            Card(
              color: provider.excelLoaded ? Colors.teal[50] : Colors.grey[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      provider.excelLoaded ? Icons.table_chart : Icons.upload_file,
                      color: provider.excelLoaded ? Colors.teal : Colors.grey,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            provider.excelLoaded
                                ? 'Costos cargados'
                                : 'Sin archivo de costos',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            provider.excelLoaded
                                ? '${provider.excelService.filasConCosto} productos con costo'
                                : 'Cargá un Excel con los costos unitarios',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Módulos
            Text('Módulos', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            // 1. Conexión
            _ModuleCard(
              icon: Icons.wifi,
              title: 'Conexión',
              subtitle: provider.isConnected
                  ? 'Sesión activa'
                  : 'Configurar ERPNext',
              color: Colors.blue,
              onTap: () => Navigator.pushNamed(context, '/config'),
            ),

            // 2. Excel
            _ModuleCard(
              icon: Icons.upload_file,
              title: 'Cargar Costos',
              subtitle: 'Archivo Excel con precios',
              color: Colors.teal,
              onTap: () => Navigator.pushNamed(context, '/excel'),
            ),

            // 3. Órdenes de Compra
            _ModuleCard(
              icon: Icons.shopping_cart,
              title: 'Órdenes de Compra',
              subtitle: provider.isConnected
                  ? 'Crear y gestionar órdenes'
                  : 'Conectate a ERPNext primero',
              color: Colors.deepOrange,
              enabled: provider.isConnected,
              onTap: () => Navigator.pushNamed(context, '/po-list'),
            ),

            // 4. Escáner
            _ModuleCard(
              icon: Icons.qr_code_scanner,
              title: 'Escanear Inventario',
              subtitle: provider.isReady
                  ? '${provider.uniqueProducts} productos contados'
                  : 'Conectá ERPNext y cargá Excel primero',
              color: provider.isReady ? Colors.green : Colors.grey,
              enabled: provider.isReady,
              onTap: () => Navigator.pushNamed(context, '/scanner'),
            ),

            // 5. Reporte
            _ModuleCard(
              icon: Icons.table_chart,
              title: 'Ver Reporte',
              subtitle: provider.uniqueProducts > 0
                  ? '${provider.totalUnitsScanned} uds — L${provider.totalInventoryValue.toStringAsFixed(2)}'
                  : 'Aún no hay datos',
              color: Colors.purple,
              enabled: provider.uniqueProducts > 0,
              onTap: () => Navigator.pushNamed(context, '/report'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget reutilizable para las tarjetas de módulo.
class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  const _ModuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: enabled ? color.withValues(alpha: 0.1) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: enabled ? color : Colors.grey),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: enabled ? null : Colors.grey,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: enabled ? Colors.grey[600] : Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: enabled ? Colors.grey : Colors.grey[300]),
            ],
          ),
        ),
      ),
    );
  }
}
