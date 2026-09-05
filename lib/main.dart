import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/purchase_order_provider.dart';
import 'providers/material_receipt_provider.dart';
import 'services/erpnext_service.dart';
import 'views/config_screen.dart';
import 'views/excel_upload_screen.dart';
import 'views/scanner_screen.dart';
import 'views/report_screen.dart';
import 'views/home_screen.dart';
import 'views/purchase_order_list_screen.dart';
import 'views/purchase_order_detail_screen.dart';
import 'views/material_receipt_list_screen.dart';
import 'views/material_receipt_detail_screen.dart';

void main() {
  // Singleton: un solo servicio de ERPNext para toda la app
  final erpNextService = ErpNextService();

  runApp(InventarioApp(erpNextService: erpNextService));
}

/// App principal de Inventario con ERPNext.
/// Versión Móvil con escáner de cámara para códigos de barras.
class InventarioApp extends StatelessWidget {
  final ErpNextService erpNextService;

  const InventarioApp({super.key, required this.erpNextService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: erpNextService),
        ChangeNotifierProvider(
          create: (_) => InventoryProvider(erpNextService: erpNextService),
        ),
        ChangeNotifierProvider(
          create: (_) => PurchaseOrderProvider(erpNextService: erpNextService),
        ),
        ChangeNotifierProvider(
          create: (_) => MaterialReceiptProvider(erpNextService: erpNextService),
        ),
      ],
      child: MaterialApp(
        title: 'Inventario ERPNext',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1976D2),
          useMaterial3: true,
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          textSelectionTheme: const TextSelectionThemeData(
            selectionColor: Colors.transparent,
            selectionHandleColor: Color(0xFF1976D2),
            cursorColor: Color(0xFF1976D2),
          ),
          inputDecorationTheme: InputDecorationTheme(
            focusColor: const Color(0xFF1976D2),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1976D2), width: 2),
            ),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
          ),
        ),
        initialRoute: '/home',
        routes: {
          '/home': (_) => const HomeScreen(),
          '/config': (_) => const ConfigScreen(),
          '/excel': (_) => const ExcelUploadScreen(),
          '/scanner': (_) => const ScannerScreen(),
          '/report': (_) => const ReportScreen(),
          '/po-list': (_) => const PurchaseOrderListScreen(),
          '/po-create': (_) => const PurchaseOrderDetailScreen(),
          '/po-detail': (_) => const PurchaseOrderDetailScreen(),
          '/mr-list': (_) => const MaterialReceiptListScreen(),
          '/mr-create': (_) => const MaterialReceiptDetailScreen(),
          '/mr-detail': (_) => const MaterialReceiptDetailScreen(),
        },
      ),
    );
  }
}
