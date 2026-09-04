import 'package:flutter_test/flutter_test.dart';

import 'package:inventario_mobile/main.dart';
import 'package:inventario_mobile/services/erpnext_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(InventarioApp(
      erpNextService: ErpNextService(),
    ));

    // Verify that the app renders without errors.
    expect(find.text('📦 Inventario ERPNext'), findsOneWidget);
  });
}
